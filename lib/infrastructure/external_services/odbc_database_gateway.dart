import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/builders/odbc_connection_builder.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_options_builder.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _QueryExecutionOutcome {
  const _QueryExecutionOutcome.success(this.response) : error = null;

  const _QueryExecutionOutcome.failure(this.error) : response = null;

  final QueryResponse? response;
  final Object? error;

  bool get isSuccess => response != null;
}

class _BatchExecutionContext {
  const _BatchExecutionContext({
    required this.connectionId,
    required this.connectionString,
    required this.deadline,
    this.directLease,
    this.ownedConnection = false,
  });

  final String connectionId;
  final String connectionString;
  final DateTime? deadline;
  final DirectOdbcConnectionLease? directLease;

  /// When true, [connectionId] was obtained via [OdbcService.connect] and must
  /// be disconnected; otherwise it is a pooled handle and must be released.
  final bool ownedConnection;
}

class _BatchTransactionStart {
  const _BatchTransactionStart(this.transactionId);

  final int? transactionId;
}

class _BatchTransactionGuard {
  _BatchTransactionGuard(this.transactionId);

  final int? transactionId;
  bool _closed = false;

  bool get isActive => transactionId != null && !_closed;

  Future<void> rollback(
    Future<void> Function(int transactionId) rollback,
  ) async {
    final id = transactionId;
    if (id == null || _closed) {
      return;
    }

    _closed = true;
    await rollback(id);
  }

  void markCommitted() {
    _closed = true;
  }
}

class _BatchConnectionState {
  _BatchConnectionState(this.connectionId);

  String? connectionId;
}

/// ODBC Database Gateway using odbc_fast package.
///
/// This implementation provides:
/// - Native Rust engine for better performance
/// - Async API (non-blocking) for Flutter
/// - Simplified code (no manual column extraction)
/// - Built-in error handling with Result types
/// - Connection pooling for reduced overhead
/// - Performance metrics collection
class OdbcDatabaseGateway implements IDatabaseGateway {
  OdbcDatabaseGateway(
    this._configRepository,
    this._service,
    IConnectionPool connectionPool,
    this._retryManager,
    this._metrics,
    this._settings, {
    FeatureFlags? featureFlags,
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    ISqlInvestigationCollector? sqlInvestigation,
  }) : _featureFlags = featureFlags,
       _connectionManager = OdbcGatewayConnectionManager(
         service: _service,
         connectionPool: connectionPool,
         directConnectionLimiter:
             directConnectionLimiter ??
             DirectOdbcConnectionLimiter(
               maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
                 _settings.poolSize,
               ),
               acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
               metricsCollector: _metrics,
             ),
         metrics: _metrics,
         directConnectionMaxProvider: () => ConnectionConstants.directOdbcConnectionConcurrency(_settings.poolSize),
       ),
       _sqlInvestigation = sqlInvestigation,
       _uuid = const Uuid();
  final OdbcService _service;
  final IAgentConfigRepository _configRepository;
  final IRetryManager _retryManager;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final OdbcGatewayConnectionManager _connectionManager;
  final FeatureFlags? _featureFlags;
  final ISqlInvestigationCollector? _sqlInvestigation;
  final Uuid _uuid;
  bool _initialized = false;
  final OdbcAdaptiveBufferCache _adaptiveBufferCache = OdbcAdaptiveBufferCache();
  final Map<String, ConnectionOptions> _connectionOptionsCache = <String, ConnectionOptions>{};
  final Map<String, ConnectionCircuitBreaker> _circuitBreakers = <String, ConnectionCircuitBreaker>{};
  static const int _multiResultSqlLogPreviewChars = 120;
  static const int _maxPreparedStatementsPerBatchConnection = 64;
  static const int _asyncRequestPendingStatus = 0;
  static const int _asyncRequestReadyStatus = 1;
  static const int _asyncRequestErrorStatus = -1;
  static const int _asyncRequestCancelledStatus = -2;
  static const Duration _asyncRequestPollInterval = Duration(milliseconds: 20);
  static const String _nativeCompatibleSqlAllowlistEnv = 'ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST';
  static final RegExp _previewSqlWhitespaceCollapse = RegExp(r'\s+');
  static final List<RegExp> _connectionStringDatabasePatterns = [
    RegExp(r'(database)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(dbn)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(initial\s+catalog)\s*=\s*[^;]*', caseSensitive: false),
  ];

  static String _previewSqlForLog(String sql) {
    final collapsed = sql.replaceAll(_previewSqlWhitespaceCollapse, ' ').trim();
    if (collapsed.length <= _multiResultSqlLogPreviewChars) {
      return collapsed;
    }
    return '${collapsed.substring(0, _multiResultSqlLogPreviewChars)}…';
  }

  bool _looksLikeTimeoutError(Object error) => OdbcErrorInspector.isTimeout(error);

  /// Gets or creates a circuit breaker for the given connection string.
  ConnectionCircuitBreaker _getCircuitBreaker(String connectionString) {
    return _circuitBreakers.putIfAbsent(
      connectionString,
      () => ConnectionCircuitBreaker(
        failureThreshold: ConnectionConstants.circuitBreakerFailureThreshold,
        resetTimeout: ConnectionConstants.circuitBreakerResetTimeout,
      ),
    );
  }

  ConnectionOptions get _connectionOptions => _connectionOptionsForTimeout(null);

  ConnectionOptions _connectionOptionsForTimeout(Duration? timeout) {
    final key = [
      timeout?.inMilliseconds ?? 0,
      _settings.loginTimeoutSeconds,
      _settings.maxResultBufferMb,
      _settings.streamingChunkSizeKb,
    ].join(':');
    return _connectionOptionsCache.putIfAbsent(
      key,
      () {
        if (timeout == null) {
          return OdbcConnectionOptionsBuilder.forQueryExecution(_settings);
        }
        return OdbcConnectionOptionsBuilder.forQueryExecutionWithTimeout(
          _settings,
          queryTimeout: timeout,
        );
      },
    );
  }

  /// Ensures ODBC environment is initialized before operations.
  Future<Result<void>> _ensureInitialized() async {
    if (_initialized) {
      return const Success(unit);
    }

    developer.log('Initializing ODBC environment', name: 'database_gateway');

    final initResult = await _service.initialize();
    return initResult.fold(
      (_) {
        _initialized = true;
        developer.log(
          'ODBC initialized successfully',
          name: 'database_gateway',
          level: 500,
        );
        return const Success(unit);
      },
      (error) {
        developer.log(
          'ODBC initialization failed',
          name: 'database_gateway',
          level: 1000,
          error: error,
        );
        return Failure(
          OdbcFailureMapper.mapConnectionError(
            error,
            operation: 'initialize_odbc',
            context: {
              'reason': 'odbc_initialization_failed',
              'user_message': 'Não foi possível inicializar o ambiente ODBC neste computador.',
            },
          ),
        );
      },
    );
  }

  String _odbcErrorMessage(Object error) => OdbcErrorInspector.message(error);

  String _bufferExpansionErrorMessage(Object error) {
    if (error is domain.Failure) {
      final rawOdbcMessage = error.context['odbc_message'];
      if (rawOdbcMessage is String && rawOdbcMessage.trim().isNotEmpty) {
        return rawOdbcMessage;
      }
    }
    return _odbcErrorMessage(error);
  }

  Exception _asException(
    Object? error, {
    required String fallbackMessage,
  }) {
    if (error is Exception) {
      return error;
    }
    if (error == null) {
      return Exception(fallbackMessage);
    }
    return Exception(error.toString());
  }

  bool _isBufferTooSmallError(Object error) {
    if (error is domain.Failure && error.context['reason'] == 'buffer_too_small') {
      return true;
    }
    if (error is domain.Failure && OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(error.message)) {
      return true;
    }
    return OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
      _bufferExpansionErrorMessage(error),
    );
  }

  void _recordSqlInvestigationExecutionFailure({
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String errorMessage,
    required bool executedInDb,
    String method = 'sql.execute',
  }) {
    if (!(_featureFlags?.enableDashboardSqlInvestigationFeed ?? true)) {
      return;
    }
    final inv = _sqlInvestigation;
    if (inv == null) {
      return;
    }
    final original = request.query;
    final effective = preparedExecution.sql;
    final effectiveForUi = original.trim() == effective.trim() ? null : effective;
    inv.recordExecutionFailure(
      method: method,
      originalSql: original,
      errorMessage: errorMessage,
      executedInDb: executedInDb,
      effectiveSql: effectiveForUi,
      rpcRequestId: request.sourceRpcRequestId,
      internalQueryId: request.id,
    );
  }

  static const int _batchSqlInvestigationPreviewMaxChars = 2000;

  String _previewBatchCommandsForInvestigation(List<SqlCommand> commands) {
    if (commands.isEmpty) {
      return '';
    }
    final joined = commands.map((SqlCommand c) => c.sql).join('\n---\n');
    if (joined.length <= _batchSqlInvestigationPreviewMaxChars) {
      return joined;
    }
    return '${joined.substring(0, _batchSqlInvestigationPreviewMaxChars)}\n... [truncated]';
  }

  void _recordSqlInvestigationBatchInfrastructureFailure({
    required String originalSql,
    required String errorMessage,
    String? rpcRequestId,
    String method = 'sql.executeBatch',
  }) {
    if (!(_featureFlags?.enableDashboardSqlInvestigationFeed ?? true)) {
      return;
    }
    final inv = _sqlInvestigation;
    if (inv == null) {
      return;
    }
    inv.recordExecutionFailure(
      method: method,
      originalSql: originalSql.isEmpty ? '(sql.executeBatch)' : originalSql,
      errorMessage: errorMessage,
      executedInDb: false,
      effectiveSql: null,
      rpcRequestId: rpcRequestId,
    );
  }

  static final RegExp _dmlPrefix = RegExp(
    r'^(insert|update|delete|merge)\s',
    caseSensitive: false,
  );

  // Returns true when the query is DML so that affectedRows carries meaningful
  // semantics. SELECT/WITH return false to avoid misleading row count reporting.
  bool _isDmlQuery(String query) => _dmlPrefix.hasMatch(query.trimLeft());

  QueryResponse _createSuccessResponse(
    QueryRequest request,
    QueryResult queryResult,
  ) {
    final rawData = OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
      queryResult,
    );
    final paginationResponse = OdbcGatewayQueryResultMapper.buildPaginationResponse(
      request.pagination,
      rawData,
    );
    final data = paginationResponse == null ? rawData : rawData.take(request.pagination!.pageSize).toList();

    final isDml = _isDmlQuery(request.query);
    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: data,
      affectedRows: isDml ? data.length : null,
      timestamp: DateTime.now(),
      columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
        queryResult.columns,
      ),
      pagination: paginationResponse,
    );
  }

  /// Builds a multi-result [QueryResponse]. Top-level [QueryResponse.affectedRows]
  /// sums row-count items when present; otherwise falls back to the first result
  /// set row count (legacy single-field compatibility for RPC).
  QueryResponse _createSuccessResponseFromMulti(
    QueryRequest request,
    QueryResultMulti queryResult,
  ) {
    final resultSets = <QueryResultSet>[];
    final items = <QueryResponseItem>[];
    var resultSetIndex = 0;
    var totalAffectedRows = 0;

    for (var itemIndex = 0; itemIndex < queryResult.items.length; itemIndex++) {
      final item = queryResult.items[itemIndex];
      if (item.resultSet != null) {
        final resultSet = QueryResultSet(
          index: resultSetIndex,
          rows: OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
            item.resultSet!,
          ),
          rowCount: item.resultSet!.rowCount,
          columnMetadata: OdbcGatewayQueryResultMapper.buildColumnMetadata(
            item.resultSet!.columns,
          ),
        );
        resultSets.add(resultSet);
        items.add(
          QueryResponseItem.resultSet(
            index: itemIndex,
            resultSet: resultSet,
          ),
        );
        resultSetIndex++;
        continue;
      }

      final rowCount = item.rowCount ?? 0;
      totalAffectedRows += rowCount;
      items.add(
        QueryResponseItem.rowCount(
          index: itemIndex,
          rowCount: rowCount,
        ),
      );
    }

    final primaryResultSet = resultSets.isNotEmpty
        ? resultSets.first
        : const QueryResultSet(index: 0, rows: [], rowCount: 0);

    return QueryResponse(
      id: _uuid.v4(),
      requestId: request.id,
      agentId: request.agentId,
      data: primaryResultSet.rows,
      affectedRows: totalAffectedRows > 0 ? totalAffectedRows : primaryResultSet.rowCount,
      timestamp: DateTime.now(),
      columnMetadata: primaryResultSet.columnMetadata,
      resultSets: resultSets,
      items: items,
    );
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    final initResult = await _ensureInitialized();

    return initResult.fold((_) async {
      if (connectionString.trim().isEmpty) {
        return Failure(
          domain.ValidationFailure('Connection string cannot be empty'),
        );
      }

      final connResult = await _service.connect(
        connectionString,
        options: _connectionOptions,
      );

      return connResult.fold(
        (connection) async {
          final disconnectResult = await _service.disconnect(
            connection.id,
          );
          return disconnectResult.fold(
            (_) => const Success(true),
            (error) => Failure(
              OdbcFailureMapper.mapConnectionError(
                error,
                operation: 'disconnect_test_connection',
              ),
            ),
          );
        },
        (error) {
          developer.log(
            'Connection test failed',
            name: 'database_gateway',
            level: 900,
            error: error,
          );
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_test_connection',
            ),
          );
        },
      );
    }, Failure.new);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
  }) async {
    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = _resolveConnectionString(
              config,
              localConfig,
              databaseOverride: database,
            );

            // Execute through circuit breaker for fail-fast behavior
            final breaker = _getCircuitBreaker(connectionString);
            return breaker.execute(
              connectionString,
              () => _executeQueryWithRetry(
                request,
                connectionString,
                localConfig,
                timeout: timeout,
              ),
            );
          },
          (domainFailure) => Failure(
            domain.ConfigurationFailure(
              'Failed to load database configuration: $domainFailure',
            ),
          ),
        );
      },
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'initialize_odbc',
          context: {
            'reason': 'odbc_initialization_failed',
            'user_message': 'Não foi possível inicializar o ambiente ODBC neste computador.',
          },
        ),
      ),
    );
  }

  DatabaseConfig _buildDatabaseConfig(Config config) {
    return DatabaseConfig(
      driverName: config.odbcDriverName,
      username: config.username,
      password: config.password ?? '',
      database: config.databaseName,
      server: config.host,
      port: config.port,
      databaseType: _mapDriverNameToDatabaseType(config.driverName),
    );
  }

  Future<Result<QueryResponse>> _executeQueryWithRetry(
    QueryRequest request,
    String connectionString,
    DatabaseConfig databaseConfig, {
    Duration? timeout,
    int maxAttempts = 3,
  }) async {
    return _executeWithRetryBudget<QueryResponse>(
      (remainingTimeout) => _executeQueryInternal(
        request,
        connectionString,
        databaseConfig,
        timeout: remainingTimeout,
      ),
      maxAttempts: maxAttempts,
      initialDelayMs: 500,
      backoffMultiplier: 2,
      timeout: timeout,
      stage: 'query',
    );
  }

  Future<Result<T>> _executeWithRetryBudget<T extends Object>(
    Future<Result<T>> Function(Duration? remainingTimeout) operation, {
    required int maxAttempts,
    required int initialDelayMs,
    required double backoffMultiplier,
    required Duration? timeout,
    required String stage,
  }) async {
    if (timeout == null) {
      return _retryManager.execute(
        () => operation(null),
        maxAttempts: maxAttempts,
        initialDelayMs: initialDelayMs,
        backoffMultiplier: backoffMultiplier,
      );
    }

    final deadline = DateTime.now().add(timeout);
    var attempts = 0;
    var delayMs = initialDelayMs;
    Result<T>? lastResult;

    while (attempts < maxAttempts) {
      attempts++;
      final remaining = _remainingTimeoutFromDeadline(deadline);
      if (remaining == null || remaining <= Duration.zero) {
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'SQL execution budget exhausted before retry attempt',
            context: {
              'timeout': true,
              'timeout_stage': 'sql',
              'stage': stage,
              'reason': '${stage}_budget_exhausted',
            },
          ),
        );
      }

      final result = await operation(remaining);
      if (result.isSuccess()) {
        return result;
      }

      lastResult = result;
      final exception = result.exceptionOrNull();
      if (exception == null || !_retryManager.isTransientFailure(exception) || attempts >= maxAttempts) {
        return result;
      }

      final remainingBeforeDelay = _remainingTimeoutFromDeadline(deadline);
      if (remainingBeforeDelay == null || remainingBeforeDelay <= Duration.zero) {
        return result;
      }

      final requestedDelay = Duration(milliseconds: delayMs);
      final boundedDelay = requestedDelay < remainingBeforeDelay ? requestedDelay : remainingBeforeDelay;
      await Future<void>.delayed(boundedDelay);
      delayMs = (delayMs * backoffMultiplier).toInt();
    }

    return lastResult ??
        Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'SQL execution failed before retry could start',
            context: {
              'reason': '${stage}_retry_failed',
              'stage': stage,
            },
          ),
        );
  }

  Future<Result<QueryResponse>> _executeQueryInternal(
    QueryRequest request,
    String connectionString,
    DatabaseConfig databaseConfig, {
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    final paginationValidation = OdbcGatewayQueryPreparation.validatePaginationForDatabase(
      request,
      databaseConfig.databaseType,
    );
    if (paginationValidation != null) {
      return Failure(paginationValidation);
    }

    final preparedExecution = OdbcGatewayQueryPreparation.prepareQueryExecution(
      request,
      databaseConfig,
    );
    final queryValidation = OdbcGatewayQueryPreparation.validateQueryExecutionMode(
      request,
      preparedExecution,
    );
    if (queryValidation != null) {
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: queryValidation.message,
        executedInDb: false,
      );
      return Failure(queryValidation);
    }
    OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
      featureFlags: _featureFlags,
      request: request,
      databaseConfig: databaseConfig,
      preparedExecution: preparedExecution,
    );

    final baseOptions = _connectionOptionsForTimeout(timeout);
    final hintedOptions = _hintedConnectionOptions(
      connectionString: connectionString,
      sql: preparedExecution.sql,
      baseOptions: baseOptions,
    );
    if (hintedOptions != null) {
      developer.log(
        'Using cached adaptive buffer hint for pooled query execution',
        name: 'database_gateway',
        level: 800,
      );
      return _executeQueryWithPool(
        request,
        connectionString,
        stopwatch,
        preparedExecution: preparedExecution,
        timeout: timeout,
        acquireOptions: hintedOptions,
      );
    }

    return _executeQueryWithPool(
      request,
      connectionString,
      stopwatch,
      preparedExecution: preparedExecution,
      timeout: timeout,
      allowNativeCompatibleAcquire: _shouldUseNativeCompatibleAcquire(
        databaseConfig: databaseConfig,
        request: request,
        preparedExecution: preparedExecution,
        acquireOptions: null,
        timeout: timeout,
      ),
    );
  }

  Future<Result<QueryResponse>> _executeQueryWithPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    required Duration? timeout,
    ConnectionOptions? acquireOptions,
    bool allowAdaptiveRetry = true,
    bool allowNativeCompatibleAcquire = false,
    DateTime? deadline,
  }) async {
    final effectiveDeadline = deadline ?? _deadlineFor(timeout);
    final poolAcquireOptions =
        acquireOptions ??
        _connectionOptionsForTimeout(
          _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        );
    final poolResult = allowNativeCompatibleAcquire
        ? await _connectionManager.acquireNativeCompatiblePooledConnection(
            connectionString,
            leaseFallbackOptions: poolAcquireOptions,
            deadline: effectiveDeadline,
            context: {'query_id': request.id},
          )
        : await _connectionManager.acquirePooledConnection(
            connectionString,
            options: poolAcquireOptions,
            deadline: effectiveDeadline,
            context: {'query_id': request.id},
          );

    if (poolResult.isError()) {
      stopwatch.stop();
      final error = poolResult.exceptionOrNull()!;
      final failure = error is domain.Failure
          ? error
          : OdbcFailureMapper.mapPoolError(
              error,
              operation: 'acquire_connection',
              context: {'query_id': request.id},
            );

      developer.log(
        'Failed to acquire connection for query ${request.id}',
        name: 'database_gateway',
        level: 1000,
        error: error,
      );

      _metrics.recordFailure(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        errorMessage: _odbcErrorMessage(error),
      );

      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: _odbcErrorMessage(error),
        executedInDb: false,
      );

      return Failure(
        failure,
      );
    }

    final connId = poolResult.getOrThrow();
    var releasedConnectionEarly = false;
    final effectiveOptions = poolAcquireOptions;

    try {
      final outcome = await _runQueryExecutionWithTimeout(
        connId: connId,
        request: request,
        preparedExecution: preparedExecution,
        connectionString: connectionString,
        timeout: _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        executionMode: allowNativeCompatibleAcquire ? 'native_compatible' : 'pooled',
      );

      if (!outcome.isSuccess) {
        final error = outcome.error!;
        if (_isInvalidConnectionIdError(error)) {
          _connectionManager.recordPooledExecutionFailure(
            connectionString: connectionString,
            connectionId: connId,
            error: error,
            stage: 'query',
          );
          _connectionManager.markConnectionForDiscard(connId);
          await _connectionManager.releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          await _connectionManager.tryRecoverPoolAfterInvalidConnectionId(connectionString);
          _metrics.recordDirectConnectionFallback();
          developer.log(
            'Pool returned invalid connection id ($connId), falling back to direct connection',
            name: 'database_gateway',
            level: 900,
          );
          return _executeQueryWithoutPool(
            request,
            connectionString,
            stopwatch,
            preparedExecution: preparedExecution,
            timeout: timeout,
          );
        }

        if (allowAdaptiveRetry && _isBufferTooSmallError(error)) {
          _metrics.recordDiagnosticReason(
            category: 'query',
            reason: 'buffer_too_small',
          );
          _connectionManager.recordPooledExecutionFailure(
            connectionString: connectionString,
            connectionId: connId,
            error: error,
            stage: 'query',
          );
          final currentBufferBytes =
              effectiveOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes;
          _adaptiveBufferCache.rememberExpandedBuffer(
            connectionString: connectionString,
            sql: preparedExecution.sql,
            currentBufferBytes: currentBufferBytes,
            errorMessage: _bufferExpansionErrorMessage(error),
          );
          developer.log(
            'Buffer too small in pooled query, retrying with expanded buffer',
            name: 'database_gateway',
            level: 900,
            error: error,
          );
          await _connectionManager.releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          return _executeQueryWithPool(
            request,
            connectionString,
            stopwatch,
            preparedExecution: preparedExecution,
            timeout: timeout,
            acquireOptions: _buildExpandedConnectionOptions(
              error,
              baseOptions: effectiveOptions,
              currentBufferBytes: currentBufferBytes,
            ),
            allowAdaptiveRetry: false,
            deadline: effectiveDeadline,
          );
        }

        stopwatch.stop();

        developer.log(
          'Query ${request.id} failed',
          name: 'database_gateway',
          level: 1000,
          error: error,
        );

        final msg = _odbcErrorMessage(error);
        _metrics.recordFailure(
          queryId: request.id,
          query: request.query,
          executionDuration: stopwatch.elapsed,
          errorMessage: msg,
        );

        _recordSqlInvestigationExecutionFailure(
          request: request,
          preparedExecution: preparedExecution,
          errorMessage: msg,
          executedInDb: true,
        );

        return Failure(
          OdbcFailureMapper.mapQueryError(
            error,
            operation: 'execute_query',
            context: {'query_id': request.id},
          ),
        );
      }

      final response = outcome.response!;
      if (_isVacuousMultiResultResponse(request, response)) {
        _metrics.recordMultiResultPoolVacuousFallback();
        developer.log(
          'Pooled executeQueryMultiFull returned no rows or row-count items; '
          'retrying on a direct connection (pool/driver quirk) '
          '(query_id=${request.id}, '
          'sql_preview=${_previewSqlForLog(preparedExecution.sql)})',
          name: 'database_gateway',
          level: 800,
        );
        _metrics.recordDirectConnectionFallback();
        await _connectionManager.releaseConnectionSafely(connId);
        releasedConnectionEarly = true;
        return _executeQueryWithoutPool(
          request,
          connectionString,
          stopwatch,
          preparedExecution: preparedExecution,
          timeout: timeout,
          afterVacuousPooledMulti: true,
          deadline: effectiveDeadline,
        );
      }

      stopwatch.stop();

      developer.log(
        'Query ${request.id} completed in ${stopwatch.elapsedMilliseconds}ms',
        name: 'database_gateway',
        level: 500,
      );

      _metrics.recordSuccess(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        rowsAffected: response.affectedRows ?? 0,
        columnCount: response.columnMetadata?.length ?? 0,
      );

      return Success(response);
    } on TimeoutException catch (error) {
      stopwatch.stop();
      _metrics.recordFailure(
        queryId: request.id,
        query: request.query,
        executionDuration: stopwatch.elapsed,
        errorMessage: 'Query execution timeout',
      );
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: 'Query execution timeout',
        executedInDb: true,
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution timeout',
          cause: error,
          context: {
            'timeout': true,
            'timeout_stage': 'sql',
            'stage': 'query',
            'reason': 'query_timeout',
            if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
          },
        ),
      );
    } finally {
      if (!releasedConnectionEarly) {
        await _connectionManager.releaseConnectionSafely(connId);
      }
    }
  }

  bool _shouldUseNativeCompatibleAcquire({
    required DatabaseConfig databaseConfig,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required ConnectionOptions? acquireOptions,
    required Duration? timeout,
  }) {
    if (!(_featureFlags?.enableOdbcExperimentalDriverAdaptivePooling ?? false)) {
      return false;
    }
    if (timeout != null) {
      return false;
    }
    if (acquireOptions != null || request.expectMultipleResults || _hasNamedParameters(preparedExecution)) {
      return false;
    }
    final isSafeResultShape =
        request.pagination != null ||
        _isNativeCompatibleProbeQuery(preparedExecution.sql) ||
        _isNativeCompatibleExplicitlyLimitedSelect(preparedExecution.sql) ||
        _isNativeCompatibleAllowlistedSql(preparedExecution.sql);
    if (!isSafeResultShape) {
      return false;
    }
    return switch (databaseConfig.databaseType) {
      DatabaseType.sqlServer || DatabaseType.postgresql => true,
      DatabaseType.sybaseAnywhere => false,
    };
  }

  bool _isNativeCompatibleProbeQuery(String sql) {
    final normalized = SqlValidator.removeComments(
      sql,
    ).replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r';+$'), '').toLowerCase();
    return RegExp(
      r'^select\s+(?:1|0|null|current_timestamp|getdate\(\)|@@version|version\(\))(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?$',
    ).hasMatch(normalized);
  }

  bool _isNativeCompatibleExplicitlyLimitedSelect(String sql) {
    final normalized = SqlValidator.removeComments(
      sql,
    ).replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r';+$'), '').toLowerCase();
    if (!normalized.startsWith('select ') && !normalized.startsWith('with ')) {
      return false;
    }
    if (_hasNativeCompatibleWildcardProjection(normalized)) {
      return false;
    }
    final limit = _extractExplicitRowLimit(normalized);
    return limit != null && limit <= 100;
  }

  bool _hasNativeCompatibleWildcardProjection(String normalizedSql) {
    return RegExp(
      r'\bselect\s+(?:top\s*\(?\s*\d+\s*\)?\s+)?\*[\s,]',
    ).hasMatch('$normalizedSql ');
  }

  int? _extractExplicitRowLimit(String normalizedSql) {
    final match = RegExp(
      r'(?:\btop\s*\(?\s*(\d+)\s*\)?|\blimit\s+(\d+)\b|\bfetch\s+first\s+(\d+)\s+rows?\s+only\b)',
    ).firstMatch(normalizedSql);
    if (match == null) {
      return null;
    }
    for (var i = 1; i <= match.groupCount; i++) {
      final value = match.group(i);
      if (value != null) {
        return int.tryParse(value);
      }
    }
    return null;
  }

  bool _isNativeCompatibleAllowlistedSql(String sql) {
    final allowlist = AppEnvironment.get(_nativeCompatibleSqlAllowlistEnv);
    if (allowlist == null || allowlist.trim().isEmpty) {
      return false;
    }
    final normalizedSql = _normalizeNativeCompatibleSql(sql);
    if (_hasNativeCompatibleWildcardProjection(normalizedSql)) {
      return false;
    }
    return allowlist
        .split('|')
        .map(_normalizeNativeCompatibleSql)
        .where((value) => value.isNotEmpty)
        .contains(normalizedSql);
  }

  String _normalizeNativeCompatibleSql(String sql) {
    return SqlValidator.removeComments(
      sql,
    ).replaceAll(RegExp(r'\s+'), ' ').trim().replaceFirst(RegExp(r';+$'), '').toLowerCase();
  }

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
  }) async {
    final effectiveTimeout =
        timeout ??
        _timeoutFromSqlExecutionOptions(options) ??
        (options.transaction ? ConnectionConstants.defaultTransactionalBatchTimeout : null);
    final batchPreview = _previewBatchCommandsForInvestigation(commands);
    if (_shouldUseParallelReadOnlyBatch(commands, options)) {
      return _executeParallelReadOnlyBatch(
        agentId: agentId,
        commands: commands,
        database: database,
        options: options,
        timeout: effectiveTimeout,
        sourceRpcRequestId: sourceRpcRequestId,
        batchSqlPreview: batchPreview,
      );
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final contextResult = await _prepareBatchExecutionContext(
        database: database,
        timeout: effectiveTimeout,
        useOwnedConnection: options.transaction,
        batchSqlPreview: batchPreview,
        sourceRpcRequestId: sourceRpcRequestId,
      );
      if (contextResult.isError()) {
        return Failure(contextResult.exceptionOrNull()!);
      }

      final context = contextResult.getOrNull()!;
      final connectionState = _BatchConnectionState(context.connectionId);
      var recycleAfterRelease = false;
      _BatchTransactionGuard? transaction;
      try {
        final beginResult = await _beginBatchTransactionIfNeeded(
          connectionId: connectionState.connectionId!,
          transactionEnabled: options.transaction,
          lockTimeout: _transactionLockTimeout(
            options: options,
            timeout: effectiveTimeout,
          ),
        );
        if (beginResult.isError()) {
          final beginFailure = beginResult.exceptionOrNull()! as domain.Failure;
          if (options.transaction && attempt == 0 && _queryFailureIndicatesInvalidConnectionId(beginFailure)) {
            recycleAfterRelease = true;
          } else {
            return Failure(beginFailure);
          }
        } else {
          if (options.transaction && context.ownedConnection) {
            _metrics.recordTransactionalBatchDirectPath();
            developer.log(
              'Transactional executeBatch uses direct ODBC connection (pool bypass)',
              name: 'database_gateway',
              level: 800,
            );
          }
          transaction = _BatchTransactionGuard(beginResult.getOrNull()!.transactionId);

          final commandResult = await _executeBatchCommands(
            context: context,
            connectionState: connectionState,
            agentId: agentId,
            commands: commands,
            options: options,
            transaction: transaction,
            sourceRpcRequestId: sourceRpcRequestId,
          );
          if (commandResult.isError()) {
            return Failure(commandResult.exceptionOrNull()!);
          }

          if (options.transaction && transaction.isActive) {
            final commitResult = await _commitBatchTransaction(
              connectionId: connectionState.connectionId!,
              transaction: transaction,
            );
            if (commitResult.isError()) {
              return Failure(commitResult.exceptionOrNull()!);
            }
          }

          return commandResult;
        }
      } on Object catch (error, stackTrace) {
        final activeConnectionId = connectionState.connectionId;
        if (options.transaction) {
          await transaction?.rollback(
            (transactionId) async {
              if (activeConnectionId == null) {
                return;
              }
              await _rollbackTransactionIfNeeded(
                activeConnectionId,
                transactionId,
              );
            },
          );
        }
        developer.log(
          'Unexpected failure during batch execution',
          name: 'database_gateway',
          level: 1000,
          error: error,
          stackTrace: stackTrace,
        );
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Batch execution failed unexpectedly',
            cause: error,
            context: {
              'reason': 'transaction_failed',
              'operation': 'transaction_unexpected_error',
              'transaction': options.transaction,
            },
          ),
        );
      } finally {
        final activeConnectionId = connectionState.connectionId;
        if (activeConnectionId != null) {
          await _releaseBatchConnection(
            _BatchExecutionContext(
              connectionId: activeConnectionId,
              connectionString: context.connectionString,
              deadline: context.deadline,
              directLease: context.directLease,
              ownedConnection: context.ownedConnection,
            ),
          );
        }
      }

      if (recycleAfterRelease) {
        if (!context.ownedConnection) {
          await _connectionManager.tryRecoverPoolAfterInvalidConnectionId(
            context.connectionString,
          );
        }
        continue;
      }
    }

    return Failure(
      domain.QueryExecutionFailure.withContext(
        message: 'Batch transaction start failed after retry',
        context: {
          'reason': 'transaction_failed',
          'operation': 'transaction_begin',
        },
      ),
    );
  }

  bool _shouldUseParallelReadOnlyBatch(
    List<SqlCommand> commands,
    SqlExecutionOptions options,
  ) {
    if (options.transaction || options.maxParallelReadOnlyBatchItems <= 1 || commands.length < 2) {
      return false;
    }
    return commands.every(
      (command) => SqlValidator.validateSelectQuery(command.sql).isSuccess(),
    );
  }

  Future<Result<List<SqlCommandResult>>> _executeParallelReadOnlyBatch({
    required String agentId,
    required List<SqlCommand> commands,
    required String? database,
    required SqlExecutionOptions options,
    required Duration? timeout,
    required String batchSqlPreview,
    String? sourceRpcRequestId,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError()) {
      return Failure(initResult.exceptionOrNull() ?? domain.ConnectionFailure('Failed to initialize ODBC for batch'));
    }

    final configResult = await _configRepository.getCurrentConfig();
    if (configResult.isError()) {
      return Failure(
        domain.ConfigurationFailure(
          'Failed to load database configuration for read-only batch execution',
        ),
      );
    }

    final config = configResult.getOrNull()!;
    final localConfig = _buildDatabaseConfig(config);
    final connectionString = _resolveConnectionString(
      config,
      localConfig,
      databaseOverride: database,
    );
    final deadline = _deadlineFor(timeout);
    final safePoolParallelism = math.max(1, _settings.poolSize ~/ 2);
    final parallelism = options.maxParallelReadOnlyBatchItems.clamp(1, safePoolParallelism);
    final results = List<SqlCommandResult?>.filled(commands.length, null);
    var cursor = 0;

    _metrics.recordReadOnlyBatchParallel(
      requestedParallelism: options.maxParallelReadOnlyBatchItems,
      effectiveParallelism: parallelism,
    );
    developer.log(
      'Executing read-only batch with controlled parallelism',
      name: 'database_gateway',
      level: 800,
      error: {
        'commands': commands.length,
        'parallelism': parallelism,
      },
    );

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= commands.length) {
          return;
        }

        final command = commands[index];
        final commandRequest = QueryRequest(
          id: _uuid.v4(),
          agentId: agentId,
          query: command.sql,
          parameters: command.params,
          timestamp: DateTime.now(),
          sourceRpcRequestId: sourceRpcRequestId,
        );
        final remainingTimeout = _remainingTimeoutFromDeadline(deadline);
        if (remainingTimeout != null && remainingTimeout <= Duration.zero) {
          results[index] = SqlCommandResult.failure(
            index: index,
            error: 'Batch SQL execution timeout',
          );
          continue;
        }

        final queryResult = await _executeQueryWithRetry(
          commandRequest,
          connectionString,
          localConfig,
          timeout: remainingTimeout ?? timeout,
          maxAttempts: 1,
        );
        results[index] = queryResult.fold(
          (response) {
            final limitedRows = truncateSqlResultRows(
              response.data,
              options.maxRows,
            );
            return SqlCommandResult.success(
              index: index,
              rows: limitedRows,
              rowCount: limitedRows.length,
              affectedRows: response.affectedRows,
              columnMetadata: response.columnMetadata,
            );
          },
          (error) {
            final message = error is domain.Failure ? error.message : error.toString();
            _recordSqlInvestigationBatchInfrastructureFailure(
              originalSql: command.sql.isEmpty ? batchSqlPreview : command.sql,
              errorMessage: message,
              rpcRequestId: sourceRpcRequestId,
            );
            return SqlCommandResult.failure(
              index: index,
              error: message,
            );
          },
        );
      }
    }

    await Future.wait(
      List.generate(parallelism, (_) => worker()),
    );

    return Success(
      results
          .asMap()
          .entries
          .map(
            (entry) =>
                entry.value ??
                SqlCommandResult.failure(
                  index: entry.key,
                  error: 'Read-only batch item did not complete',
                ),
          )
          .toList(),
    );
  }

  Future<void> _releaseBatchConnection(_BatchExecutionContext context) async {
    if (context.ownedConnection) {
      final directLease = context.directLease;
      if (directLease == null) {
        await _connectionManager.disconnectOwnedConnectionSafely(
          context.connectionId,
          operation: 'batch_direct_disconnect',
        );
        return;
      }

      await _connectionManager.disconnectOwnedConnectionAndReleaseLease(
        connectionId: context.connectionId,
        directLease: directLease,
        operation: 'batch_direct_disconnect',
      );
      return;
    }
    await _connectionManager.releaseConnectionSafely(context.connectionId);
  }

  Future<Result<_BatchExecutionContext>> _prepareBatchExecutionContext({
    required String? database,
    required Duration? timeout,
    required bool useOwnedConnection,
    required String batchSqlPreview,
    String? sourceRpcRequestId,
  }) async {
    final initResult = await _ensureInitialized();
    if (initResult.isError()) {
      final failure = initResult.exceptionOrNull();
      if (failure != null) {
        return Failure(failure);
      }
      return Failure(
        domain.ConnectionFailure('Failed to initialize ODBC for batch'),
      );
    }

    final configResult = await _configRepository.getCurrentConfig();
    if (configResult.isError()) {
      return Failure(
        domain.ConfigurationFailure(
          'Failed to load database configuration for batch execution',
        ),
      );
    }

    final config = configResult.getOrNull()!;
    final localConfig = _buildDatabaseConfig(config);
    final connectionString = _resolveConnectionString(
      config,
      localConfig,
      databaseOverride: database,
    );
    final deadline = timeout == null ? null : DateTime.now().add(timeout);

    if (useOwnedConnection) {
      final leaseResult = await _connectionManager.acquireDirectLease(
        operation: 'batch_transaction',
        deadline: deadline,
      );
      if (leaseResult.isError()) {
        final err = leaseResult.exceptionOrNull()!;
        _recordSqlInvestigationBatchInfrastructureFailure(
          originalSql: batchSqlPreview,
          errorMessage: _odbcErrorMessage(err),
          rpcRequestId: sourceRpcRequestId,
        );
        return Failure(err);
      }
      final directLease = leaseResult.getOrThrow();
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: _connectionOptionsForTimeout(
          _remainingTimeoutFromDeadline(deadline) ?? timeout,
        ),
      );
      return connectResult.fold(
        (connection) {
          return Success(
            _BatchExecutionContext(
              connectionId: connection.id,
              connectionString: connectionString,
              deadline: deadline,
              directLease: directLease,
              ownedConnection: true,
            ),
          );
        },
        (error) {
          directLease.release();
          _recordSqlInvestigationBatchInfrastructureFailure(
            originalSql: batchSqlPreview,
            errorMessage: _odbcErrorMessage(error),
            rpcRequestId: sourceRpcRequestId,
          );
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_direct',
              context: {
                'operation': 'batch_execute',
                'transaction': true,
              },
            ),
          );
        },
      );
    }

    final poolResult = await _connectionManager.acquirePooledConnection(
      connectionString,
      options: _connectionOptionsForTimeout(
        _remainingTimeoutFromDeadline(deadline) ?? timeout,
      ),
      deadline: deadline,
      context: {'operation': 'batch_execute'},
    );
    if (poolResult.isError()) {
      final error = poolResult.exceptionOrNull()!;
      final failure = error is domain.Failure
          ? error
          : OdbcFailureMapper.mapPoolError(
              error,
              operation: 'acquire_connection',
              context: {'operation': 'batch_execute'},
            );
      _recordSqlInvestigationBatchInfrastructureFailure(
        originalSql: batchSqlPreview,
        errorMessage: _odbcErrorMessage(error),
        rpcRequestId: sourceRpcRequestId,
      );
      return Failure(
        failure,
      );
    }

    return Success(
      _BatchExecutionContext(
        connectionId: poolResult.getOrNull()!,
        connectionString: connectionString,
        deadline: deadline,
      ),
    );
  }

  Future<Result<_BatchTransactionStart>> _beginBatchTransactionIfNeeded({
    required String connectionId,
    required bool transactionEnabled,
    required Duration? lockTimeout,
  }) async {
    if (!transactionEnabled) {
      return const Success(_BatchTransactionStart(null));
    }

    final beginResult = await _service.beginTransaction(
      connectionId,
      savepointDialect: SavepointDialect.auto,
      accessMode: TransactionAccessMode.readWrite,
      lockTimeout: lockTimeout,
    );
    if (beginResult.isError()) {
      final error = beginResult.exceptionOrNull()!;
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Failed to start transaction',
          cause: error,
          context: {
            'reason': 'transaction_failed',
            'operation': 'transaction_begin',
            'error': _odbcErrorMessage(error),
          },
        ),
      );
    }

    return Success(_BatchTransactionStart(beginResult.getOrNull()));
  }

  Future<Result<void>> _commitBatchTransaction({
    required String connectionId,
    required _BatchTransactionGuard transaction,
  }) async {
    final transactionId = transaction.transactionId;
    if (transactionId == null) {
      return const Success(unit);
    }

    final commitResult = await _service.commitTransaction(
      connectionId,
      transactionId,
    );
    if (commitResult.isError()) {
      final error = commitResult.exceptionOrNull()!;
      await transaction.rollback(
        (id) => _rollbackTransactionIfNeeded(connectionId, id),
      );
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Failed to commit transaction',
          cause: error,
          context: {
            'reason': 'transaction_failed',
            'operation': 'transaction_commit',
            'error': _odbcErrorMessage(error),
          },
        ),
      );
    }

    transaction.markCommitted();
    return const Success(unit);
  }

  Future<Result<List<SqlCommandResult>>> _executeBatchCommands({
    required _BatchExecutionContext context,
    required _BatchConnectionState connectionState,
    required String agentId,
    required List<SqlCommand> commands,
    required SqlExecutionOptions options,
    required _BatchTransactionGuard transaction,
    String? sourceRpcRequestId,
  }) async {
    final results = <SqlCommandResult>[];
    final repeatedPreparedKeys = _collectRepeatedPreparedKeys(commands);
    final preparedStatements = <String, int>{};

    try {
      for (var i = 0; i < commands.length; i++) {
        final command = commands[i];
        final validation = SqlValidator.validateSqlForExecution(command.sql);
        if (validation.isError()) {
          final failure = validation.exceptionOrNull()! as domain.Failure;
          if (options.transaction) {
            await transaction.rollback(
              (transactionId) => _rollbackTransactionIfNeeded(
                context.connectionId,
                transactionId,
              ),
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Transaction aborted due to command validation failure',
                cause: failure,
                context: {
                  'reason': 'transaction_failed',
                  'operation': 'transaction_validation',
                  'failedIndex': i,
                  'detail': failure.message,
                },
              ),
            );
          }
          results.add(SqlCommandResult.failure(index: i, error: failure.message));
          continue;
        }

        final commandRequest = QueryRequest(
          id: _uuid.v4(),
          agentId: agentId,
          query: command.sql,
          parameters: command.params,
          timestamp: DateTime.now(),
          sourceRpcRequestId: sourceRpcRequestId,
        );
        final preparedExecution = OdbcPreparedQueryExecution(
          sql: command.sql,
          parameters: command.params,
        );
        final remainingTimeout = _remainingTimeout(context.deadline);

        Future<_QueryExecutionOutcome> executeCurrentCommand() async {
          final currentConnectionId = connectionState.connectionId;
          if (currentConnectionId == null) {
            return _QueryExecutionOutcome.failure(
              StateError('batch_connection_unavailable'),
            );
          }

          final key = _preparedStatementKeyFor(preparedExecution);
          final usePrepared = repeatedPreparedKeys.contains(key);
          return usePrepared
              ? _runPreparedBatchExecutionWithTimeout(
                  connectionId: currentConnectionId,
                  request: commandRequest,
                  preparedExecution: preparedExecution,
                  preparedStatements: preparedStatements,
                  statementKey: key,
                  timeout: remainingTimeout,
                )
              : _runQueryExecutionWithTimeout(
                  connId: currentConnectionId,
                  request: commandRequest,
                  preparedExecution: preparedExecution,
                  connectionString: context.connectionString,
                  timeout: remainingTimeout,
                  preferPreparedTimeout: options.transaction,
                  executionMode: options.transaction ? 'batch_transaction' : 'batch',
                );
        }

        try {
          var outcome = await executeCurrentCommand();

          if (!outcome.isSuccess) {
            var error = outcome.error!;
            var failure = OdbcFailureMapper.mapQueryError(
              error,
              operation: 'execute_batch_item',
              context: {
                'command_index': i,
                'transaction': options.transaction,
              },
            );

            if (options.transaction) {
              await transaction.rollback(
                (transactionId) => _rollbackTransactionIfNeeded(
                  connectionState.connectionId!,
                  transactionId,
                ),
              );
              _recordSqlInvestigationExecutionFailure(
                request: commandRequest,
                preparedExecution: preparedExecution,
                errorMessage: failure.message,
                executedInDb: true,
                method: 'sql.executeBatch',
              );
              return Failure(
                domain.QueryExecutionFailure.withContext(
                  message: 'Transaction aborted due to command failure',
                  cause: error,
                  context: {
                    'reason': 'transaction_failed',
                    'operation': 'transaction_execute',
                    'failedIndex': i,
                    'detail': failure.message,
                  },
                ),
              );
            }

            if (_shouldRecoverNonTransactionalBatchConnection(failure)) {
              outcome = await _retryBatchCommandAfterConnectionFailure(
                context: context,
                connectionState: connectionState,
                preparedStatements: preparedStatements,
                failure: failure,
                executeCommand: executeCurrentCommand,
              );
              if (outcome.isSuccess) {
                final response = outcome.response!;
                final limitedRows = truncateSqlResultRows(
                  response.data,
                  options.maxRows,
                );
                results.add(
                  SqlCommandResult.success(
                    index: i,
                    rows: limitedRows,
                    rowCount: limitedRows.length,
                    affectedRows: response.affectedRows,
                    columnMetadata: response.columnMetadata,
                  ),
                );
                continue;
              }

              error = outcome.error!;
              failure = OdbcFailureMapper.mapQueryError(
                error,
                operation: 'execute_batch_item',
                context: {
                  'command_index': i,
                  'transaction': options.transaction,
                },
              );
            }

            _recordSqlInvestigationExecutionFailure(
              request: commandRequest,
              preparedExecution: preparedExecution,
              errorMessage: failure.message,
              executedInDb: true,
              method: 'sql.executeBatch',
            );

            results.add(
              SqlCommandResult.failure(index: i, error: failure.message),
            );
            continue;
          }

          final response = outcome.response!;
          final limitedRows = truncateSqlResultRows(
            response.data,
            options.maxRows,
          );
          results.add(
            SqlCommandResult.success(
              index: i,
              rows: limitedRows,
              rowCount: limitedRows.length,
              affectedRows: response.affectedRows,
              columnMetadata: response.columnMetadata,
            ),
          );
        } on TimeoutException catch (error) {
          if (options.transaction) {
            await transaction.rollback(
              (transactionId) => _rollbackTransactionIfNeeded(
                connectionState.connectionId!,
                transactionId,
              ),
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Transaction aborted due to timeout',
                cause: error,
                context: {
                  'reason': 'transaction_failed',
                  'operation': 'transaction_timeout',
                  'failedIndex': i,
                  'timeout': true,
                  'timeout_stage': 'sql',
                  'stage': 'batch',
                },
              ),
            );
          }
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Batch SQL execution timeout',
              cause: error,
              context: {
                'reason': 'query_timeout',
                'timeout': true,
                'timeout_stage': 'sql',
                'stage': 'batch',
              },
            ),
          );
        }
      }
    } finally {
      final activeConnectionId = connectionState.connectionId;
      if (activeConnectionId != null) {
        await _closePreparedStatements(
          activeConnectionId,
          preparedStatements.values,
        );
      }
    }

    return Success(results);
  }

  bool _shouldRecoverNonTransactionalBatchConnection(domain.Failure failure) {
    if (failure is domain.ConnectionFailure) {
      return true;
    }

    if (_queryFailureIndicatesInvalidConnectionId(failure)) {
      return true;
    }

    return failure.context['connectionFailed'] == true;
  }

  Future<_QueryExecutionOutcome> _retryBatchCommandAfterConnectionFailure({
    required _BatchExecutionContext context,
    required _BatchConnectionState connectionState,
    required Map<String, int> preparedStatements,
    required domain.Failure failure,
    required Future<_QueryExecutionOutcome> Function() executeCommand,
  }) async {
    final currentConnectionId = connectionState.connectionId;
    if (currentConnectionId == null) {
      return _QueryExecutionOutcome.failure(failure);
    }

    if (preparedStatements.isNotEmpty) {
      await _closePreparedStatements(
        currentConnectionId,
        preparedStatements.values,
      );
      preparedStatements.clear();
    }

    _connectionManager.markConnectionForDiscard(currentConnectionId);
    _connectionManager.recordPooledExecutionFailure(
      connectionString: context.connectionString,
      connectionId: currentConnectionId,
      error: failure,
      stage: 'batch',
    );
    await _connectionManager.releaseConnectionSafely(currentConnectionId);
    connectionState.connectionId = null;

    if (_queryFailureIndicatesInvalidConnectionId(failure)) {
      await _connectionManager.tryRecoverPoolAfterInvalidConnectionId(context.connectionString);
    }

    final reacquireResult = await _connectionManager.acquirePooledConnection(
      context.connectionString,
      options: _connectionOptionsForTimeout(
        _remainingTimeoutFromDeadline(context.deadline),
      ),
      deadline: context.deadline,
      context: {'operation': 'batch_reacquire_connection'},
    );
    if (reacquireResult.isError()) {
      return _QueryExecutionOutcome.failure(
        reacquireResult.exceptionOrNull() ?? failure,
      );
    }

    connectionState.connectionId = reacquireResult.getOrThrow();
    developer.log(
      'Recovered pooled batch connection after command failure',
      name: 'database_gateway',
      level: 800,
      error: {
        'connection_string': context.connectionString,
        'failed_reason': failure.context['reason'] ?? failure.message,
      },
    );
    return executeCommand();
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  }) async {
    final initResult = await _ensureInitialized();

    return initResult.fold(
      (_) async {
        final configResult = await _configRepository.getCurrentConfig();

        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = _resolveConnectionString(
              config,
              localConfig,
              databaseOverride: database,
            );

            return _executeNonQueryWithRetry(
              query,
              parameters,
              connectionString,
              timeout: timeout,
            );
          },
          (domainFailure) => Failure(
            domain.ConfigurationFailure(
              'Failed to get config: $domainFailure',
            ),
          ),
        );
      },
      Failure.new,
    );
  }

  Future<Result<int>> _executeNonQueryWithRetry(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
  }) async {
    return _executeWithRetryBudget<int>(
      (remainingTimeout) => _executeNonQueryInternal(
        query,
        parameters,
        connectionString,
        timeout: remainingTimeout,
      ),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
      timeout: timeout,
      stage: 'query',
    );
  }

  Future<Result<int>> _executeNonQueryInternal(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
  }) async {
    final deadline = _deadlineFor(timeout);
    final poolResult = await _connectionManager.acquirePooledConnection(
      connectionString,
      options: _connectionOptionsForTimeout(timeout),
      deadline: deadline,
    );

    if (poolResult.isError()) {
      final error = poolResult.exceptionOrNull()!;
      return Failure(
        error is domain.Failure
            ? error
            : OdbcFailureMapper.mapPoolError(
                error,
                operation: 'acquire_connection',
              ),
      );
    }

    final connId = poolResult.getOrNull()!;
    var releasedConnectionEarly = false;

    try {
      // Use named parameters if available
      final result = await _runNonQueryWithTimeout(
        connectionId: connId,
        query: query,
        parameters: parameters,
        timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
      );

      if (result.isError()) {
        final error = result.exceptionOrNull()!;
        if (_isInvalidConnectionIdError(error)) {
          _connectionManager.recordPooledExecutionFailure(
            connectionString: connectionString,
            connectionId: connId,
            error: error,
            stage: 'non_query',
          );
          _connectionManager.markConnectionForDiscard(connId);
          await _connectionManager.releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          await _connectionManager.tryRecoverPoolAfterInvalidConnectionId(connectionString);
          _metrics.recordDirectConnectionFallback();
          developer.log(
            'Pool returned invalid connection id ($connId) for non-query, falling back to direct connection',
            name: 'database_gateway',
            level: 900,
          );
          return _executeNonQueryWithoutPool(
            query,
            parameters,
            connectionString,
            timeout: timeout,
            deadline: deadline,
          );
        }
      }

      return result.fold(
        (queryResult) => Success(queryResult.rowCount),
        (error) => Failure(
          OdbcFailureMapper.mapQueryError(
            error,
            operation: 'execute_non_query',
          ),
        ),
      );
    } on TimeoutException catch (error) {
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Non-query execution timeout',
          cause: error,
          context: {
            'timeout': true,
            'timeout_stage': 'sql',
            'stage': 'query',
            'reason': 'query_timeout',
            if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
          },
        ),
      );
    } finally {
      if (!releasedConnectionEarly) {
        await _connectionManager.releaseConnectionSafely(connId);
      }
    }
  }

  Future<_QueryExecutionOutcome> _runQueryExecutionWithTimeout({
    required String connId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String connectionString,
    Duration? timeout,
    bool preferPreparedTimeout = true,
    String executionMode = 'pooled',
  }) async {
    final stopwatch = Stopwatch()..start();
    final usesMultiResultExecution = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
      request,
      preparedExecution,
    );
    final usesPreparedTimeout = _shouldUsePreparedTimeoutPath(
      preparedExecution: preparedExecution,
      timeout: timeout,
      preferPreparedTimeout: preferPreparedTimeout,
      usesMultiResultExecution: usesMultiResultExecution,
    );
    try {
      if (usesPreparedTimeout) {
        return await _runPreparedQueryExecution(
          connectionId: connId,
          request: request,
          preparedExecution: preparedExecution,
          timeout: timeout,
        );
      }

      if (timeout != null && !usesMultiResultExecution && !_hasNamedParameters(preparedExecution)) {
        final asyncResult = await _runNativeAsyncQueryWithTimeout(
          connectionId: connId,
          query: preparedExecution.sql,
          timeout: timeout,
        );
        if (asyncResult.isSuccess()) {
          return _QueryExecutionOutcome.success(
            _createSuccessResponse(request, asyncResult.getOrThrow()),
          );
        }

        final asyncError = asyncResult.exceptionOrNull();
        if (asyncError is! UnsupportedFeatureError) {
          return _QueryExecutionOutcome.failure(asyncError);
        }
      }

      if (timeout == null) {
        return await _runQueryExecution(connId, request, preparedExecution);
      }

      return await _runQueryExecution(
        connId,
        request,
        preparedExecution,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      _metrics.recordQueryTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: 'query_timeout',
      );
      if (!usesPreparedTimeout) {
        await _cancelConnectionForTimeout(connId, connectionString);
      }
      developer.log(
        'SQL query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    } finally {
      stopwatch.stop();
      _metrics.recordSqlExecutionTime(
        stopwatch.elapsed,
        mode: executionMode,
      );
    }
  }

  bool _shouldUsePreparedTimeoutPath({
    required OdbcPreparedQueryExecution preparedExecution,
    required Duration? timeout,
    required bool preferPreparedTimeout,
    required bool usesMultiResultExecution,
  }) {
    return timeout != null &&
        preferPreparedTimeout &&
        !usesMultiResultExecution &&
        _hasNamedParameters(preparedExecution);
  }

  bool _hasNamedParameters(OdbcPreparedQueryExecution preparedExecution) {
    return preparedExecution.parameters?.isNotEmpty ?? false;
  }

  Set<String> _collectRepeatedPreparedKeys(
    List<SqlCommand> commands,
  ) {
    final counts = <String, int>{};
    for (final command in commands) {
      final key = _preparedStatementKeyFor(
        OdbcPreparedQueryExecution(
          sql: command.sql,
          parameters: command.params,
        ),
      );
      counts[key] = (counts[key] ?? 0) + 1;
    }

    return counts.entries.where((entry) => entry.value > 1).map((entry) => entry.key).toSet();
  }

  String _preparedStatementKeyFor(
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    final parameterNames = List<String>.of(
      preparedExecution.parameters?.keys ?? const <String>[],
    );
    parameterNames.sort();
    return '${preparedExecution.sql}::${parameterNames.join(',')}';
  }

  Future<_QueryExecutionOutcome> _runPreparedBatchExecutionWithTimeout({
    required String connectionId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required Map<String, int> preparedStatements,
    required String statementKey,
    Duration? timeout,
  }) async {
    final deadline = _deadlineFor(timeout);
    final stmtId = await _getOrPrepareStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      preparedStatements: preparedStatements,
      statementKey: statementKey,
      timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
    );
    if (stmtId.isError()) {
      return _QueryExecutionOutcome.failure(
        stmtId.exceptionOrNull() ?? StateError('prepare_statement_failed'),
      );
    }

    final preparedStatementId = stmtId.getOrThrow();
    final result = await _executePreparedStatementWithTimeout(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      statementId: preparedStatementId,
      timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
    );
    return result.fold(
      (queryResult) => _QueryExecutionOutcome.success(
        _createSuccessResponse(request, queryResult),
      ),
      _QueryExecutionOutcome.failure,
    );
  }

  Future<_QueryExecutionOutcome> _runPreparedQueryExecution({
    required String connectionId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    Duration? timeout,
  }) async {
    final deadline = _deadlineFor(timeout);
    final preparedStatements = <String, int>{};
    final statementKey = _preparedStatementKeyFor(preparedExecution);
    try {
      final stmtId = await _getOrPrepareStatement(
        connectionId: connectionId,
        preparedExecution: preparedExecution,
        preparedStatements: preparedStatements,
        statementKey: statementKey,
        timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
      );
      if (stmtId.isError()) {
        return _QueryExecutionOutcome.failure(
          stmtId.exceptionOrNull() ?? StateError('prepare_statement_failed'),
        );
      }

      final result = await _executePreparedStatementWithTimeout(
        connectionId: connectionId,
        preparedExecution: preparedExecution,
        statementId: stmtId.getOrThrow(),
        timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
      );
      return result.fold(
        (queryResult) => _QueryExecutionOutcome.success(
          _createSuccessResponse(request, queryResult),
        ),
        _QueryExecutionOutcome.failure,
      );
    } finally {
      await _closePreparedStatements(
        connectionId,
        preparedStatements.values,
      );
    }
  }

  Future<Result<int>> _getOrPrepareStatement({
    required String connectionId,
    required OdbcPreparedQueryExecution preparedExecution,
    required Map<String, int> preparedStatements,
    required String statementKey,
    Duration? timeout,
  }) async {
    final existingStmtId = preparedStatements[statementKey];
    if (existingStmtId != null) {
      preparedStatements.remove(statementKey);
      preparedStatements[statementKey] = existingStmtId;
      _metrics.recordPreparedStatementReuse();
      return Success(existingStmtId);
    }

    _metrics.recordPreparedStatementCacheMiss();

    final timeoutMs = timeout?.inMilliseconds ?? 0;
    final prepareStopwatch = Stopwatch()..start();
    final prepareResult = preparedExecution.parameters != null && preparedExecution.parameters!.isNotEmpty
        ? await _service.prepareNamed(
            connectionId,
            preparedExecution.sql,
            timeoutMs: timeoutMs,
          )
        : await _service.prepare(
            connectionId,
            preparedExecution.sql,
            timeoutMs: timeoutMs,
          );
    prepareStopwatch.stop();
    _metrics.recordPreparedPrepareTime(prepareStopwatch.elapsed);

    return prepareResult.fold(
      (stmtId) {
        if (preparedStatements.length >= _maxPreparedStatementsPerBatchConnection) {
          final oldestKey = preparedStatements.keys.first;
          final oldestStmtId = preparedStatements.remove(oldestKey);
          if (oldestStmtId != null) {
            unawaited(_closePreparedStatements(connectionId, <int>[oldestStmtId]));
          }
        }
        preparedStatements[statementKey] = stmtId;
        return Success(stmtId);
      },
      Failure.new,
    );
  }

  Future<Result<QueryResult>> _executePreparedStatement({
    required String connectionId,
    required OdbcPreparedQueryExecution preparedExecution,
    required int stmtId,
    StatementOptions? options,
  }) {
    final parameters = preparedExecution.parameters;
    if (parameters != null && parameters.isNotEmpty) {
      return _service.executePreparedNamed(
        connectionId,
        stmtId,
        parameters,
        options,
      );
    }

    return _service.executePrepared(
      connectionId,
      stmtId,
      null,
      options,
    );
  }

  Future<Result<QueryResult>> _executePreparedStatementWithTimeout({
    required String connectionId,
    required OdbcPreparedQueryExecution preparedExecution,
    required int statementId,
    Duration? timeout,
  }) async {
    final statementOptions = timeout == null ? null : StatementOptions(timeout: timeout);
    final execution = _executePreparedStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      stmtId: statementId,
      options: statementOptions,
    );
    if (timeout == null) {
      return execution;
    }

    return execution.timeout(
      timeout,
      onTimeout: () async {
        _connectionManager.markConnectionForDiscard(connectionId);
        unawaited(
          _cancelPreparedStatementForTimeout(
            connectionId: connectionId,
            statementId: statementId,
          ),
        );
        throw TimeoutException('Prepared statement execution deadline exceeded');
      },
    );
  }

  Future<void> _closePreparedStatements(
    String connectionId,
    Iterable<int> stmtIds,
  ) async {
    for (final stmtId in stmtIds) {
      try {
        await _service.closeStatement(connectionId, stmtId);
      } on Object catch (error) {
        developer.log(
          'Failed to close prepared statement after execution',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      }
    }
  }

  Future<Result<QueryResult>> _runNonQueryWithTimeout({
    required String connectionId,
    required String query,
    Map<String, dynamic>? parameters,
    Duration? timeout,
    String executionMode = 'non_query',
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (timeout == null) {
        if (parameters != null && parameters.isNotEmpty) {
          return await _service.executeQueryNamed(
            connectionId,
            query,
            parameters,
          );
        }
        return await _service.executeQuery(
          query,
          connectionId: connectionId,
        );
      }

      if (parameters == null || parameters.isEmpty) {
        final asyncResult = await _runNativeAsyncQueryWithTimeout(
          connectionId: connectionId,
          query: query,
          timeout: timeout,
        );
        if (asyncResult.isSuccess()) {
          return asyncResult;
        }

        final asyncError = asyncResult.exceptionOrNull();
        if (asyncError is! UnsupportedFeatureError) {
          return Failure(
            _asException(
              asyncError,
              fallbackMessage: 'async_sql_execution_failed',
            ),
          );
        }
      }

      final preparedExecution = OdbcPreparedQueryExecution(
        sql: query,
        parameters: parameters,
      );
      final preparedStatements = <String, int>{};
      final statementKey = _preparedStatementKeyFor(preparedExecution);
      try {
        final stmtId = await _getOrPrepareStatement(
          connectionId: connectionId,
          preparedExecution: preparedExecution,
          preparedStatements: preparedStatements,
          statementKey: statementKey,
          timeout: timeout,
        );
        if (stmtId.isError()) {
          final error = stmtId.exceptionOrNull();
          final failure = error is Exception ? error : Exception('prepare_statement_failed');
          return Failure(failure);
        }

        return await _executePreparedStatementWithTimeout(
          connectionId: connectionId,
          preparedExecution: preparedExecution,
          statementId: stmtId.getOrThrow(),
          timeout: timeout,
        );
      } finally {
        await _closePreparedStatements(
          connectionId,
          preparedStatements.values,
        );
      }
    } on TimeoutException catch (error) {
      _metrics.recordQueryTimeout();
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: 'query_timeout',
      );
      developer.log(
        'SQL non-query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    } finally {
      stopwatch.stop();
      _metrics.recordSqlExecutionTime(
        stopwatch.elapsed,
        mode: executionMode,
      );
    }
  }

  Future<Result<QueryResult>> _runNativeAsyncQueryWithTimeout({
    required String connectionId,
    required String query,
    required Duration timeout,
  }) async {
    final startResult = await _service.executeAsyncStart(
      connectionId,
      query,
    );
    if (startResult.isError()) {
      return Failure(startResult.exceptionOrNull()!);
    }

    final requestId = startResult.getOrThrow();
    final deadline = DateTime.now().add(timeout);

    try {
      while (true) {
        final pollResult = await _service.asyncPoll(requestId);
        if (pollResult.isError()) {
          return Failure(pollResult.exceptionOrNull()!);
        }

        final status = pollResult.getOrThrow();
        switch (status) {
          case _asyncRequestReadyStatus:
            final result = await _service.asyncGetResult(requestId);
            return result.fold(Success.new, Failure.new);
          case _asyncRequestPendingStatus:
            final remaining = deadline.difference(DateTime.now());
            if (remaining <= Duration.zero) {
              await _cancelAsyncRequestForTimeout(
                connectionId: connectionId,
                requestId: requestId,
              );
              throw TimeoutException('Async SQL execution deadline exceeded');
            }
            final delay = remaining < _asyncRequestPollInterval ? remaining : _asyncRequestPollInterval;
            await Future<void>.delayed(delay);
            continue;
          case _asyncRequestErrorStatus:
          case _asyncRequestCancelledStatus:
            final result = await _service.asyncGetResult(requestId);
            if (result.isError()) {
              return Failure(result.exceptionOrNull()!);
            }
            return Failure(
              Exception(
                'Async SQL request completed with status $status without error payload',
              ),
            );
          default:
            return Failure(
              Exception('Unexpected async SQL request status: $status'),
            );
        }
      }
    } finally {
      await _freeAsyncRequestSafely(requestId);
    }
  }

  Future<void> _cancelConnectionForTimeout(
    String connectionId,
    String _,
  ) async {
    _connectionManager.markConnectionForDiscard(connectionId);
    _metrics.recordTimeoutCancelFailure();
    developer.log(
      'SQL query timed out; connection marked for discard because no statement handle is available to cancel',
      name: 'database_gateway',
      level: 900,
    );
  }

  Future<void> _cancelPreparedStatementForTimeout({
    required String connectionId,
    required int statementId,
  }) async {
    final cancelResult = await _service.cancelStatement(
      connectionId,
      statementId,
    );
    cancelResult.fold(
      (_) {
        _metrics.recordTimeoutCancelSuccess();
      },
      (error) {
        _connectionManager.markConnectionForDiscard(connectionId);
        _metrics.recordTimeoutCancelFailure();
        developer.log(
          'Failed to cancel prepared statement after timeout',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      },
    );
  }

  Future<void> _cancelAsyncRequestForTimeout({
    required String connectionId,
    required int requestId,
  }) async {
    _connectionManager.markConnectionForDiscard(connectionId);
    final cancelResult = await _service.asyncCancel(requestId);
    cancelResult.fold(
      (_) {
        _metrics.recordTimeoutCancelSuccess();
      },
      (error) {
        _metrics.recordTimeoutCancelFailure();
        developer.log(
          'Failed to cancel async SQL request after timeout',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      },
    );
  }

  Future<void> _freeAsyncRequestSafely(int requestId) async {
    final freeResult = await _service.asyncFree(requestId);
    if (freeResult.isSuccess()) {
      return;
    }

    developer.log(
      'Failed to free async SQL request after completion',
      name: 'database_gateway',
      level: 900,
      error: freeResult.exceptionOrNull(),
    );
  }

  Duration? _remainingTimeout(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      throw TimeoutException('Execution deadline exceeded');
    }
    return remaining;
  }

  Duration? _timeoutFromSqlExecutionOptions(SqlExecutionOptions options) {
    if (options.timeoutMs <= 0) {
      return null;
    }
    return Duration(milliseconds: options.timeoutMs);
  }

  Duration? _transactionLockTimeout({
    required SqlExecutionOptions options,
    required Duration? timeout,
  }) {
    return timeout ?? _timeoutFromSqlExecutionOptions(options);
  }

  DateTime? _deadlineFor(Duration? timeout) {
    return timeout == null ? null : DateTime.now().add(timeout);
  }

  Duration? _remainingTimeoutFromDeadline(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : remaining;
  }

  Future<void> _rollbackTransactionIfNeeded(
    String connectionId,
    int? transactionId,
  ) async {
    if (transactionId == null) {
      return;
    }
    _metrics.recordTransactionRollbackAttempt();
    final rollback = await _service.rollbackTransaction(
      connectionId,
      transactionId,
    );
    if (rollback.isError()) {
      _metrics.recordTransactionRollbackFailure();
      developer.log(
        'Failed to rollback transaction',
        name: 'database_gateway',
        level: 900,
        error: rollback.exceptionOrNull(),
      );
    }
  }

  Future<Result<QueryResponse>> _executeQueryWithoutPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    ConnectionOptions? options,
    Duration? timeout,
    bool afterVacuousPooledMulti = false,
    bool allowAdaptiveRetry = true,
    DateTime? deadline,
  }) async {
    final effectiveDeadline = deadline ?? _deadlineFor(timeout);
    final leaseResult = await _connectionManager.acquireDirectLease(
      operation: 'query_direct',
      deadline: effectiveDeadline,
    );
    if (leaseResult.isError()) {
      stopwatch.stop();
      final leaseFailure = leaseResult.exceptionOrNull()!;
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: leaseFailure.toString(),
        executedInDb: false,
      );
      return Failure(leaseFailure);
    }
    final directLease = leaseResult.getOrThrow();
    var directLeaseReleased = false;
    void releaseDirectLease() {
      if (directLeaseReleased) {
        return;
      }
      directLeaseReleased = true;
      directLease.release();
    }

    final effectiveOptions =
        options ??
        _connectionOptionsForTimeout(
          _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        );

    try {
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: effectiveOptions,
      );
      return await connectResult.fold(
        (connection) async {
          var connectionCleanedUp = false;

          Future<void> cleanupOwnedConnection() async {
            if (connectionCleanedUp) {
              return;
            }
            connectionCleanedUp = true;
            await _connectionManager.disconnectOwnedConnectionAndReleaseLease(
              connectionId: connection.id,
              directLease: directLease,
              operation: 'query_direct_disconnect',
            );
          }

          try {
            final outcome = await _runQueryExecutionWithTimeout(
              connId: connection.id,
              request: request,
              preparedExecution: preparedExecution,
              connectionString: connectionString,
              timeout: _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
              executionMode: 'direct',
            );
            if (!outcome.isSuccess) {
              final error = outcome.error!;
              if (_isBufferTooSmallError(error)) {
                _metrics.recordDiagnosticReason(
                  category: 'query',
                  reason: 'buffer_too_small',
                );
                final currentBufferBytes =
                    effectiveOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes;
                _adaptiveBufferCache.rememberExpandedBuffer(
                  connectionString: connectionString,
                  sql: preparedExecution.sql,
                  currentBufferBytes: currentBufferBytes,
                  errorMessage: _bufferExpansionErrorMessage(error),
                );

                if (allowAdaptiveRetry) {
                  await cleanupOwnedConnection();
                  developer.log(
                    'Buffer too small in direct query, retrying with expanded buffer',
                    name: 'database_gateway',
                    level: 900,
                    error: error,
                  );
                  return _executeQueryWithoutPool(
                    request,
                    connectionString,
                    stopwatch,
                    preparedExecution: preparedExecution,
                    options: _buildExpandedConnectionOptions(
                      error,
                      baseOptions: effectiveOptions,
                      currentBufferBytes: currentBufferBytes,
                    ),
                    timeout: timeout,
                    afterVacuousPooledMulti: afterVacuousPooledMulti,
                    allowAdaptiveRetry: false,
                    deadline: effectiveDeadline,
                  );
                }
              }
              stopwatch.stop();
              _metrics.recordFailure(
                queryId: request.id,
                query: request.query,
                executionDuration: stopwatch.elapsed,
                errorMessage: _odbcErrorMessage(error),
              );
              _recordSqlInvestigationExecutionFailure(
                request: request,
                preparedExecution: preparedExecution,
                errorMessage: _odbcErrorMessage(error),
                executedInDb: true,
              );
              return Failure(
                OdbcFailureMapper.mapQueryError(
                  error,
                  operation: 'execute_query_direct',
                  context: {'query_id': request.id},
                ),
              );
            }

            final response = outcome.response!;
            if (afterVacuousPooledMulti && _isVacuousMultiResultResponse(request, response)) {
              _metrics.recordMultiResultDirectStillVacuous();
              developer.log(
                'Direct connection multi-result still vacuous after pooled empty '
                'payload (query_id=${request.id}, '
                'sql_preview=${_previewSqlForLog(preparedExecution.sql)})',
                name: 'database_gateway',
                level: 800,
              );
            }
            stopwatch.stop();
            _metrics.recordSuccess(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              rowsAffected: response.affectedRows ?? 0,
              columnCount: response.columnMetadata?.length ?? 0,
            );
            return Success(response);
          } on TimeoutException catch (error) {
            stopwatch.stop();
            _metrics.recordFailure(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              errorMessage: 'Query execution timeout',
            );
            _recordSqlInvestigationExecutionFailure(
              request: request,
              preparedExecution: preparedExecution,
              errorMessage: 'Query execution timeout',
              executedInDb: true,
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'SQL execution timeout',
                cause: error,
                context: {
                  'timeout': true,
                  'timeout_stage': 'sql',
                  'stage': 'query',
                  'reason': 'query_timeout',
                  if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
                },
              ),
            );
          } finally {
            await cleanupOwnedConnection();
          }
        },
        (error) {
          if (_looksLikeTimeoutError(error)) {
            _metrics.recordConnectTimeout();
          }
          stopwatch.stop();
          _metrics.recordFailure(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            errorMessage: _odbcErrorMessage(error),
          );
          _recordSqlInvestigationExecutionFailure(
            request: request,
            preparedExecution: preparedExecution,
            errorMessage: _odbcErrorMessage(error),
            executedInDb: false,
          );
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_direct',
              context: {'query_id': request.id},
            ),
          );
        },
      );
    } finally {
      releaseDirectLease();
    }
  }

  Future<Result<int>> _executeNonQueryWithoutPool(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
    DateTime? deadline,
  }) async {
    final effectiveDeadline = deadline ?? _deadlineFor(timeout);
    final leaseResult = await _connectionManager.acquireDirectLease(
      operation: 'non_query_direct',
      deadline: effectiveDeadline,
    );
    if (leaseResult.isError()) {
      return Failure(leaseResult.exceptionOrNull()!);
    }
    final directLease = leaseResult.getOrThrow();
    var directLeaseReleased = false;
    void releaseDirectLease() {
      if (directLeaseReleased) {
        return;
      }
      directLeaseReleased = true;
      directLease.release();
    }

    try {
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: _connectionOptionsForTimeout(
          _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        ),
      );
      return await connectResult.fold(
        (connection) async {
          try {
            final result = await _runNonQueryWithTimeout(
              connectionId: connection.id,
              query: query,
              parameters: parameters,
              timeout: _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
              executionMode: 'direct_non_query',
            );

            return result.fold(
              (queryResult) => Success(queryResult.rowCount),
              (error) => Failure(
                OdbcFailureMapper.mapQueryError(
                  error,
                  operation: 'execute_non_query_direct',
                ),
              ),
            );
          } on TimeoutException catch (error) {
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Non-query execution timeout',
                cause: error,
                context: {
                  'timeout': true,
                  'timeout_stage': 'sql',
                  'stage': 'query',
                  'reason': 'query_timeout',
                  if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
                },
              ),
            );
          } finally {
            await _connectionManager.disconnectOwnedConnectionAndReleaseLease(
              connectionId: connection.id,
              directLease: directLease,
              operation: 'non_query_direct_disconnect',
            );
          }
        },
        (error) {
          if (_looksLikeTimeoutError(error)) {
            _metrics.recordConnectTimeout();
          }
          return Failure(
            OdbcFailureMapper.mapConnectionError(
              error,
              operation: 'connect_direct',
            ),
          );
        },
      );
    } finally {
      releaseDirectLease();
    }
  }

  String _resolveConnectionString(
    Config config,
    DatabaseConfig databaseConfig, {
    String? databaseOverride,
  }) {
    final override = databaseOverride?.trim();
    final resolved = config.resolveConnectionString().trim();

    if (override != null && override.isNotEmpty) {
      final overriddenDatabaseConfig = DatabaseConfig(
        driverName: databaseConfig.driverName,
        username: databaseConfig.username,
        password: databaseConfig.password,
        database: override,
        server: databaseConfig.server,
        port: databaseConfig.port,
        databaseType: databaseConfig.databaseType,
      );
      if (resolved.isNotEmpty) {
        return _overrideDatabaseInConnectionString(resolved, override);
      }
      return OdbcConnectionBuilder.build(overriddenDatabaseConfig);
    }

    if (resolved.isNotEmpty) {
      return resolved;
    }
    return OdbcConnectionBuilder.build(databaseConfig);
  }

  String _overrideDatabaseInConnectionString(
    String connectionString,
    String database,
  ) {
    var updated = connectionString;

    var replaced = false;
    for (final pattern in _connectionStringDatabasePatterns) {
      if (pattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(pattern, (match) {
          replaced = true;
          return '${match.group(1)}=$database';
        });
      }
    }

    if (replaced) {
      return updated;
    }

    final suffix = updated.endsWith(';') ? '' : ';';
    return '$updated${suffix}DATABASE=$database';
  }

  ConnectionOptions _buildExpandedConnectionOptions(
    Object error, {
    required ConnectionOptions baseOptions,
    required int currentBufferBytes,
  }) {
    final expandedBufferBytes = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
      currentBufferBytes: currentBufferBytes,
      errorMessage: _bufferExpansionErrorMessage(error),
    );
    final baseInitialBufferBytes =
        baseOptions.initialResultBufferBytes ?? ConnectionConstants.defaultInitialResultBufferBytes;
    final initialResultBufferBytes = baseInitialBufferBytes < expandedBufferBytes
        ? baseInitialBufferBytes
        : expandedBufferBytes;

    developer.log(
      'Expanding max result buffer for retry: '
      '$currentBufferBytes -> $expandedBufferBytes bytes',
      name: 'database_gateway',
      level: 800,
    );

    return ConnectionOptions(
      loginTimeout: baseOptions.loginTimeout,
      queryTimeout: baseOptions.queryTimeout,
      maxResultBufferBytes: expandedBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: baseOptions.autoReconnectOnConnectionLost,
      maxReconnectAttempts: baseOptions.maxReconnectAttempts,
      reconnectBackoff: baseOptions.reconnectBackoff,
    );
  }

  ConnectionOptions? _hintedConnectionOptions({
    required String connectionString,
    required String sql,
    required ConnectionOptions baseOptions,
  }) {
    final hintedBufferBytes = _adaptiveBufferCache.lookup(
      connectionString: connectionString,
      sql: sql,
    );
    if (hintedBufferBytes == null) {
      return null;
    }

    final initialBufferBytes =
        baseOptions.initialResultBufferBytes ?? ConnectionConstants.defaultInitialResultBufferBytes;
    return ConnectionOptions(
      loginTimeout: baseOptions.loginTimeout,
      queryTimeout: baseOptions.queryTimeout,
      maxResultBufferBytes: hintedBufferBytes,
      initialResultBufferBytes: initialBufferBytes < hintedBufferBytes ? initialBufferBytes : hintedBufferBytes,
      autoReconnectOnConnectionLost: baseOptions.autoReconnectOnConnectionLost,
      maxReconnectAttempts: baseOptions.maxReconnectAttempts,
      reconnectBackoff: baseOptions.reconnectBackoff,
    );
  }

  /// True when [request] asked for multi-result execution but the ODBC layer
  /// reported success with no materialized rows and no non-zero row-count
  /// items. Some pool/driver paths return an empty [QueryResultMulti] payload
  /// even though a direct connection returns data for the same SQL.
  bool _isVacuousMultiResultResponse(
    QueryRequest request,
    QueryResponse response,
  ) {
    if (!request.expectMultipleResults) {
      return false;
    }
    final hasRows = response.data.isNotEmpty || response.resultSets.any((QueryResultSet s) => s.rows.isNotEmpty);
    final hasNonZeroRowCount = response.items.any(
      (QueryResponseItem i) => i.isRowCount && (i.rowCount ?? 0) > 0,
    );
    return !hasRows && !hasNonZeroRowCount;
  }

  bool _queryFailureIndicatesInvalidConnectionId(domain.Failure failure) {
    return _isInvalidConnectionIdError(failure);
  }

  bool _isInvalidConnectionIdError(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  DatabaseType _mapDriverNameToDatabaseType(String driverName) {
    return switch (driverName) {
      'SQL Server' => DatabaseType.sqlServer,
      'PostgreSQL' => DatabaseType.postgresql,
      'SQL Anywhere' => DatabaseType.sybaseAnywhere,
      _ => DatabaseType.sqlServer,
    };
  }

  Future<_QueryExecutionOutcome> _runQueryExecution(
    String connectionId,
    QueryRequest request,
    OdbcPreparedQueryExecution preparedExecution,
  ) async {
    if (OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
      request,
      preparedExecution,
    )) {
      final queryResult = await _service.executeQueryMultiFull(
        connectionId,
        preparedExecution.sql,
      );
      return queryResult.fold(
        (success) => _QueryExecutionOutcome.success(
          _createSuccessResponseFromMulti(request, success),
        ),
        _QueryExecutionOutcome.failure,
      );
    }

    final queryResult = preparedExecution.parameters != null && preparedExecution.parameters!.isNotEmpty
        ? await _service.executeQueryNamed(
            connectionId,
            preparedExecution.sql,
            preparedExecution.parameters!,
          )
        : await _service.executeQuery(
            preparedExecution.sql,
            connectionId: connectionId,
          );

    return queryResult.fold(
      (success) => _QueryExecutionOutcome.success(
        _createSuccessResponse(request, success),
      ),
      _QueryExecutionOutcome.failure,
    );
  }
}
