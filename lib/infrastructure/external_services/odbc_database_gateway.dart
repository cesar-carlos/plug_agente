import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/application/validation/sql_validator.dart';
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
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
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
    this._connectionPool,
    this._retryManager,
    this._metrics,
    this._settings, {
    FeatureFlags? featureFlags,
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    ISqlInvestigationCollector? sqlInvestigation,
  }) : _featureFlags = featureFlags,
       _directConnectionLimiter =
           directConnectionLimiter ??
           DirectOdbcConnectionLimiter(
             maxConcurrent: _settings.poolSize,
             acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
             metricsCollector: _metrics,
           ),
       _sqlInvestigation = sqlInvestigation,
       _uuid = const Uuid();
  final OdbcService _service;
  final IAgentConfigRepository _configRepository;
  final IConnectionPool _connectionPool;
  final IRetryManager _retryManager;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final DirectOdbcConnectionLimiter _directConnectionLimiter;
  final FeatureFlags? _featureFlags;
  final ISqlInvestigationCollector? _sqlInvestigation;
  final Uuid _uuid;
  bool _initialized = false;
  final OdbcAdaptiveBufferCache _adaptiveBufferCache = OdbcAdaptiveBufferCache();
  final Set<String> _connectionsToDiscard = <String>{};
  final Map<String, DateTime> _lastRecycleAttempt = <String, DateTime>{};
  final Map<String, ConnectionCircuitBreaker> _circuitBreakers = <String, ConnectionCircuitBreaker>{};
  static const int _multiResultSqlLogPreviewChars = 120;
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

  bool _looksLikeTimeoutError(Object error) {
    final message = _odbcErrorMessage(error).toLowerCase();
    return message.contains('timeout') || message.contains('timed out');
  }

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

  ConnectionOptions get _connectionOptions => OdbcConnectionOptionsBuilder.forQueryExecution(_settings);

  ConnectionOptions _connectionOptionsForTimeout(Duration? timeout) {
    if (timeout == null) {
      return _connectionOptions;
    }

    return OdbcConnectionOptionsBuilder.forQueryExecutionWithTimeout(
      _settings,
      queryTimeout: timeout,
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

  String _odbcErrorMessage(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
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
  }) async {
    return _retryManager.execute(
      () => _executeQueryInternal(
        request,
        connectionString,
        databaseConfig,
        timeout: timeout,
      ),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
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
    final parameterValidation = OdbcGatewayQueryPreparation.validateParameterCount(
      preparedExecution,
    );
    if (parameterValidation != null) {
      _recordSqlInvestigationExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: parameterValidation.message,
        executedInDb: false,
      );
      return Failure(parameterValidation);
    }

    OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
      featureFlags: _featureFlags,
      request: request,
      databaseConfig: databaseConfig,
      preparedExecution: preparedExecution,
    );

    final hintedOptions = _hintedConnectionOptions(
      connectionString: connectionString,
      sql: preparedExecution.sql,
    );
    if (hintedOptions != null) {
      developer.log(
        'Using cached adaptive buffer hint for direct query execution',
        name: 'database_gateway',
        level: 800,
      );
      return _executeQueryWithoutPool(
        request,
        connectionString,
        stopwatch,
        options: hintedOptions,
        preparedExecution: preparedExecution,
        timeout: timeout,
      );
    }

    final poolResult = await _connectionPool.acquire(connectionString);

    if (poolResult.isError()) {
      stopwatch.stop();
      final error = poolResult.exceptionOrNull()!;

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
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'acquire_connection',
          context: {'query_id': request.id},
        ),
      );
    }

    final connId = poolResult.getOrNull()!;
    var releasedConnectionEarly = false;

    try {
      final outcome = await _runQueryExecutionWithTimeout(
        connId: connId,
        request: request,
        preparedExecution: preparedExecution,
        connectionString: connectionString,
        timeout: timeout,
      );

      if (!outcome.isSuccess) {
        final error = outcome.error!;
        if (_isInvalidConnectionIdError(error)) {
          _markConnectionForDiscard(connId);
          await _releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          await _tryRecoverPoolAfterInvalidConnectionId(connectionString);
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
        if (OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
          _odbcErrorMessage(error),
        )) {
          _adaptiveBufferCache.rememberExpandedBuffer(
            connectionString: connectionString,
            sql: preparedExecution.sql,
            currentBufferBytes:
                _connectionOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes,
            errorMessage: _odbcErrorMessage(error),
          );
          developer.log(
            'Buffer too small in pooled query, retrying with expanded buffer',
            name: 'database_gateway',
            level: 900,
            error: error,
          );
          _metrics.recordDirectConnectionFallback();
          return _executeQueryWithoutPool(
            request,
            connectionString,
            stopwatch,
            options: _buildExpandedConnectionOptions(error),
            preparedExecution: preparedExecution,
            timeout: timeout,
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
        return _executeQueryWithoutPool(
          request,
          connectionString,
          stopwatch,
          preparedExecution: preparedExecution,
          timeout: timeout,
          afterVacuousPooledMulti: true,
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
        await _releaseConnectionSafely(connId);
      }
    }
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
      var recycleAfterRelease = false;
      _BatchTransactionGuard? transaction;
      try {
        final beginResult = await _beginBatchTransactionIfNeeded(
          connectionId: context.connectionId,
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
              connectionId: context.connectionId,
              transaction: transaction,
            );
            if (commitResult.isError()) {
              return Failure(commitResult.exceptionOrNull()!);
            }
          }

          return commandResult;
        }
      } on Object catch (error, stackTrace) {
        if (options.transaction) {
          await transaction?.rollback(
            (transactionId) => _rollbackTransactionIfNeeded(
              context.connectionId,
              transactionId,
            ),
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
        await _releaseBatchConnection(context);
      }

      if (recycleAfterRelease) {
        if (!context.ownedConnection) {
          await _tryRecoverPoolAfterInvalidConnectionId(
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

  Future<void> _releaseBatchConnection(_BatchExecutionContext context) async {
    if (context.ownedConnection) {
      try {
        context.directLease?.release();
        await _disconnectOwnedConnectionSafely(
          context.connectionId,
          operation: 'batch_direct_disconnect',
        );
      } finally {
        context.directLease?.release();
      }
      return;
    }
    await _releaseConnectionSafely(context.connectionId);
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
      final leaseResult = await _directConnectionLimiter.acquire(
        operation: 'batch_transaction',
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
      final connectResult = await _service.connect(
        connectionString,
        options: _connectionOptionsForTimeout(timeout),
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

    final poolResult = await _connectionPool.acquire(connectionString);
    if (poolResult.isError()) {
      final error = poolResult.exceptionOrNull()!;
      _recordSqlInvestigationBatchInfrastructureFailure(
        originalSql: batchSqlPreview,
        errorMessage: _odbcErrorMessage(error),
        rpcRequestId: sourceRpcRequestId,
      );
      return Failure(
        OdbcFailureMapper.mapPoolError(
          error,
          operation: 'acquire_connection',
          context: {'operation': 'batch_execute'},
        ),
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
        final parameterValidation = OdbcGatewayQueryPreparation.validateParameterCount(
          preparedExecution,
        );
        if (parameterValidation != null) {
          if (options.transaction) {
            await transaction.rollback(
              (transactionId) => _rollbackTransactionIfNeeded(
                context.connectionId,
                transactionId,
              ),
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Transaction aborted due to invalid prepared statement parameters',
                cause: parameterValidation,
                context: {
                  'reason': 'transaction_failed',
                  'operation': 'transaction_validation',
                  'failedIndex': i,
                  'detail': parameterValidation.message,
                },
              ),
            );
          }
          results.add(
            SqlCommandResult.failure(index: i, error: parameterValidation.message),
          );
          continue;
        }

        final remainingTimeout = _remainingTimeout(context.deadline);
        try {
          final key = _preparedStatementKeyFor(preparedExecution);
          final usePrepared = repeatedPreparedKeys.contains(key);
          final outcome = usePrepared
              ? await _runPreparedBatchExecutionWithTimeout(
                  connectionId: context.connectionId,
                  request: commandRequest,
                  preparedExecution: preparedExecution,
                  preparedStatements: preparedStatements,
                  statementKey: key,
                  timeout: remainingTimeout,
                )
              : await _runQueryExecutionWithTimeout(
                  connId: context.connectionId,
                  request: commandRequest,
                  preparedExecution: preparedExecution,
                  connectionString: context.connectionString,
                  timeout: remainingTimeout,
                );

          if (!outcome.isSuccess) {
            final error = outcome.error!;
            final failure = OdbcFailureMapper.mapQueryError(
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
                  context.connectionId,
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
                context.connectionId,
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
      await _closePreparedStatements(
        context.connectionId,
        preparedStatements.values,
      );
    }

    return Success(results);
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
    return _retryManager.execute(
      () => _executeNonQueryInternal(
        query,
        parameters,
        connectionString,
        timeout: timeout,
      ),
      maxAttempts: 3,
      initialDelayMs: 500,
      backoffMultiplier: 2,
    );
  }

  Future<Result<int>> _executeNonQueryInternal(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
  }) async {
    final poolResult = await _connectionPool.acquire(connectionString);

    if (poolResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapPoolError(
          poolResult.exceptionOrNull()!,
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
        timeout: timeout,
      );

      if (result.isError()) {
        final error = result.exceptionOrNull()!;
        if (_isInvalidConnectionIdError(error)) {
          _markConnectionForDiscard(connId);
          await _releaseConnectionSafely(connId);
          releasedConnectionEarly = true;
          await _tryRecoverPoolAfterInvalidConnectionId(connectionString);
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
        await _releaseConnectionSafely(connId);
      }
    }
  }

  Future<_QueryExecutionOutcome> _runQueryExecutionWithTimeout({
    required String connId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String connectionString,
    Duration? timeout,
  }) async {
    if (timeout != null &&
        !OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          request,
          preparedExecution,
        )) {
      return _runPreparedQueryExecution(
        connectionId: connId,
        request: request,
        preparedExecution: preparedExecution,
        timeout: timeout,
      );
    }

    if (timeout == null) {
      return _runQueryExecution(connId, request, preparedExecution);
    }

    try {
      return await _runQueryExecution(
        connId,
        request,
        preparedExecution,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      _metrics.recordQueryTimeout();
      await _cancelConnectionForTimeout(connId, connectionString);
      developer.log(
        'SQL query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    }
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
    final stmtId = await _getOrPrepareStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      preparedStatements: preparedStatements,
      statementKey: statementKey,
      timeout: timeout,
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
      timeout: timeout,
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
        return _QueryExecutionOutcome.failure(
          stmtId.exceptionOrNull() ?? StateError('prepare_statement_failed'),
        );
      }

      final result = await _executePreparedStatementWithTimeout(
        connectionId: connectionId,
        preparedExecution: preparedExecution,
        statementId: stmtId.getOrThrow(),
        timeout: timeout,
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
      _metrics.recordPreparedStatementReuse();
      return Success(existingStmtId);
    }

    final timeoutMs = timeout?.inMilliseconds ?? 0;
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

    return prepareResult.fold(
      (stmtId) {
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
        await _cancelPreparedStatementForTimeout(
          connectionId: connectionId,
          statementId: statementId,
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
      await _service.closeStatement(connectionId, stmtId);
    }
  }

  Future<Result<QueryResult>> _runNonQueryWithTimeout({
    required String connectionId,
    required String query,
    Map<String, dynamic>? parameters,
    Duration? timeout,
  }) async {
    if (timeout == null) {
      if (parameters != null && parameters.isNotEmpty) {
        return _service.executeQueryNamed(
          connectionId,
          query,
          parameters,
        );
      }
      return _service.executeQuery(
        query,
        connectionId: connectionId,
      );
    }

    try {
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
      developer.log(
        'SQL non-query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    }
  }

  Future<void> _cancelConnectionForTimeout(
    String connectionId,
    String _,
  ) async {
    _markConnectionForDiscard(connectionId);
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
        _markConnectionForDiscard(connectionId);
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
  }) async {
    final leaseResult = await _directConnectionLimiter.acquire(
      operation: 'query_direct',
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

    final connectResult = await _service.connect(
      connectionString,
      options: options ?? _connectionOptionsForTimeout(timeout),
    );

    try {
      return await connectResult.fold(
        (connection) async {
          try {
            final outcome = await _runQueryExecutionWithTimeout(
              connId: connection.id,
              request: request,
              preparedExecution: preparedExecution,
              connectionString: connectionString,
              timeout: timeout,
            );
            if (!outcome.isSuccess) {
              final error = outcome.error!;
              if (OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(
                _odbcErrorMessage(error),
              )) {
                final currentBufferBytes =
                    (options ?? _connectionOptions).maxResultBufferBytes ??
                    ConnectionConstants.defaultMaxResultBufferBytes;
                _adaptiveBufferCache.rememberExpandedBuffer(
                  connectionString: connectionString,
                  sql: preparedExecution.sql,
                  currentBufferBytes: currentBufferBytes,
                  errorMessage: _odbcErrorMessage(error),
                );
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
            releaseDirectLease();
            await _disconnectOwnedConnectionSafely(
              connection.id,
              operation: 'query_direct_disconnect',
            );
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
  }) async {
    final leaseResult = await _directConnectionLimiter.acquire(
      operation: 'non_query_direct',
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

    final connectResult = await _service.connect(
      connectionString,
      options: _connectionOptionsForTimeout(timeout),
    );

    try {
      return await connectResult.fold(
        (connection) async {
          try {
            final result = await _runNonQueryWithTimeout(
              connectionId: connection.id,
              query: query,
              parameters: parameters,
              timeout: timeout,
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
            releaseDirectLease();
            await _disconnectOwnedConnectionSafely(
              connection.id,
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

  Future<void> _disconnectOwnedConnectionSafely(
    String connectionId, {
    required String operation,
  }) async {
    _connectionsToDiscard.remove(connectionId);
    final disconnectResult = await _service.disconnect(connectionId);
    if (disconnectResult.isSuccess()) {
      return;
    }

    final disconnectError = disconnectResult.exceptionOrNull()!;
    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to disconnect owned ODBC connection: $connectionId ($operation)',
      name: 'database_gateway',
      level: 900,
      error: disconnectError,
    );
  }

  Future<void> _releaseConnectionSafely(String connectionId) async {
    final shouldDiscard = _connectionsToDiscard.remove(connectionId);
    final releaseResult = shouldDiscard
        ? await _connectionPool.discard(connectionId)
        : await _connectionPool.release(connectionId);
    if (releaseResult.isSuccess()) {
      return;
    }

    final releaseError = releaseResult.exceptionOrNull()!;
    _metrics.recordPoolReleaseFailure();
    developer.log(
      'Failed to release pooled connection: $connectionId',
      name: 'database_gateway',
      level: 900,
      error: releaseError,
    );
  }

  void _markConnectionForDiscard(String connectionId) {
    _connectionsToDiscard.add(connectionId);
  }

  ConnectionOptions _buildExpandedConnectionOptions(Object error) {
    final currentBufferBytes = OdbcConnectionOptionsBuilder.clampedMaxResultBufferMb(_settings) * 1024 * 1024;
    final expandedBufferBytes = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
      currentBufferBytes: currentBufferBytes,
      errorMessage: _odbcErrorMessage(error),
    );
    final initialResultBufferBytes = expandedBufferBytes < ConnectionConstants.defaultInitialResultBufferBytes
        ? expandedBufferBytes
        : ConnectionConstants.defaultInitialResultBufferBytes;

    developer.log(
      'Expanding max result buffer for retry: '
      '$currentBufferBytes -> $expandedBufferBytes bytes',
      name: 'database_gateway',
      level: 800,
    );

    return ConnectionOptions(
      loginTimeout: Duration(seconds: _settings.loginTimeoutSeconds),
      queryTimeout: ConnectionConstants.defaultQueryTimeout,
      maxResultBufferBytes: expandedBufferBytes,
      initialResultBufferBytes: initialResultBufferBytes,
      autoReconnectOnConnectionLost: true,
      maxReconnectAttempts: ConnectionConstants.defaultMaxReconnectAttempts,
      reconnectBackoff: ConnectionConstants.defaultReconnectBackoff,
    );
  }

  ConnectionOptions? _hintedConnectionOptions({
    required String connectionString,
    required String sql,
  }) {
    final hintedBufferBytes = _adaptiveBufferCache.lookup(
      connectionString: connectionString,
      sql: sql,
    );
    if (hintedBufferBytes == null) {
      return null;
    }

    final baseOptions = _connectionOptions;
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

  Future<void> _tryRecoverPoolAfterInvalidConnectionId(
    String connectionString,
  ) async {
    final now = DateTime.now();
    final lastAttempt = _lastRecycleAttempt[connectionString];
    if (lastAttempt != null && now.difference(lastAttempt) < const Duration(seconds: 5)) {
      developer.log(
        'Skipping pool recycle: recent recycle attempt (<5s ago)',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    final activeCountResult = await _connectionPool.getActiveCount();
    final activeCount = activeCountResult.getOrNull();
    if (activeCount != null && activeCount > 1) {
      developer.log(
        'Skipping broad pool recycle because other ODBC leases are active',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    _lastRecycleAttempt[connectionString] = now;
    final recycleResult = await _connectionPool.recycle(connectionString);
    if (recycleResult.isSuccess()) {
      _metrics.recordPoolRecycle();
      developer.log(
        'Pool recycled after invalid connection id',
        name: 'database_gateway',
        level: 800,
      );
      return;
    }

    _metrics.recordPoolRecycleFailure();
    developer.log(
      'Failed to recycle pool after invalid connection id',
      name: 'database_gateway',
      level: 900,
      error: recycleResult.exceptionOrNull(),
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
    final ctx = failure.context;
    final err = ctx['error'] != null ? ctx['error'].toString() : failure.message;
    return _isInvalidConnectionIdError(err);
  }

  bool _isInvalidConnectionIdError(Object error) {
    final message = _odbcErrorMessage(error).toLowerCase();

    if (error is ValidationError) {
      return message.contains('invalid connection id');
    }

    if (error is ConnectionError) {
      if (error.nativeCode == 100000) {
        return true;
      }
      return message.contains('invalid connection id');
    }

    if (error is OdbcError || error is QueryError) {
      return message.contains('invalid connection id');
    }

    return message.contains('invalid connection id');
  }

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
