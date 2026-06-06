import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:odbc_fast/odbc_fast.dart' as odbc show DatabaseType;
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/homogeneous_insert_batch_planner.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_rewriter.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/external_services/query_execution_outcome.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _BatchExecutionContext {
  const _BatchExecutionContext({
    required this.connectionId,
    required this.connectionString,
    required this.deadline,
    this.directLease,
    this.ownedConnection = false,
    this.nativeCompatibleAcquire = false,
  });

  final String connectionId;
  final String connectionString;
  final DateTime? deadline;
  final DirectOdbcConnectionLease? directLease;

  /// When true, [connectionId] was obtained via [OdbcService.connect] and must
  /// be disconnected; otherwise it is a pooled handle and must be released.
  final bool ownedConnection;

  /// True when the handle came from the native-compatible adaptive pool path.
  final bool nativeCompatibleAcquire;
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
class OdbcDatabaseGateway implements IDatabaseGateway, IPoolDiscardInflightDiagnostics {
  OdbcDatabaseGateway(
    this._configSource,
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
       _readOnlyBatchParallelSemaphore = PoolSemaphore(_safeReadOnlyBatchParallelism(_settings.poolSize)),
       _sqlInvestigation = sqlInvestigation,
       _nativeCompatiblePolicy = NativeCompatibleAcquirePolicy(featureFlags: featureFlags),
       _optionsResolver = OdbcConnectionOptionsResolver(_settings),
       _resultEncodingExecutor = OdbcResultEncodingExecutor(_service),
       _txManager = OdbcBatchTransactionManager(service: _service, metrics: _metrics),
       _uuid = const Uuid() {
    _statementExecutor = OdbcStatementExecutor(
      service: _service,
      metrics: _metrics,
      markConnectionForDiscard: _connectionManager.markConnectionForDiscard,
    );
    _queryRunner = OdbcQueryRunner(
      service: _service,
      metrics: _metrics,
      statementExecutor: _statementExecutor,
      resultEncodingExecutor: _resultEncodingExecutor,
      markConnectionForDiscard: _connectionManager.markConnectionForDiscard,
    );
    _bulkInsertExecutor = OdbcBulkInsertExecutor(
      connectionManager: _connectionManager,
      optionsResolver: _optionsResolver,
      service: _service,
      metrics: _metrics,
      settings: _settings,
      parallelPool: connectionPool is AdaptiveOdbcConnectionPool
          ? connectionPool.nativeBulkInsertPool
          : null,
    );
    _readOnlyBatchParallelExecutor = OdbcReadOnlyBatchParallelExecutor(
      connectionManager: _connectionManager,
      queryRunner: _queryRunner,
      optionsResolver: _optionsResolver,
      metrics: _metrics,
      parallelSemaphore: _readOnlyBatchParallelSemaphore,
      uuid: _uuid,
      recordInfrastructureFailure: _recordSqlInvestigationBatchInfrastructureFailure,
    );
  }

  @override
  int get poolDiscardInflightCount => _connectionManager.poolDiscardInflightCount;

  @override
  Future<void> reconcilePoolDiscardInflight() => _connectionManager.reconcilePoolDiscardInflight();
  final OdbcService _service;
  final IQueryConfigSource _configSource;
  final IRetryManager _retryManager;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final OdbcGatewayConnectionManager _connectionManager;
  final FeatureFlags? _featureFlags;
  final ISqlInvestigationCollector? _sqlInvestigation;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final OdbcResultEncodingExecutor _resultEncodingExecutor;
  final OdbcBatchTransactionManager _txManager;
  late final OdbcStatementExecutor _statementExecutor;
  late final OdbcQueryRunner _queryRunner;
  late final OdbcBulkInsertExecutor _bulkInsertExecutor;
  late final OdbcReadOnlyBatchParallelExecutor _readOnlyBatchParallelExecutor;
  final Uuid _uuid;
  final PoolSemaphore _readOnlyBatchParallelSemaphore;
  bool _initialized = false;
  Future<Result<void>>? _initialization;
  final ConnectionCircuitBreakerCache _circuitBreakers = ConnectionCircuitBreakerCache(
    factory: () => ConnectionCircuitBreaker(
      failureThreshold: ConnectionConstants.circuitBreakerFailureThreshold,
      resetTimeout: ConnectionConstants.circuitBreakerResetTimeout,
    ),
  );
  static const int _multiResultSqlLogPreviewChars = 120;
  static final RegExp _previewSqlWhitespaceCollapse = RegExp(r'\s+');

  static String _previewSqlForLog(String sql) {
    final collapsed = sql.replaceAll(_previewSqlWhitespaceCollapse, ' ').trim();
    if (collapsed.length <= _multiResultSqlLogPreviewChars) {
      return collapsed;
    }
    return '${collapsed.substring(0, _multiResultSqlLogPreviewChars)}…';
  }

  static int _safeReadOnlyBatchParallelism(int poolSize) {
    return OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(poolSize);
  }

  bool _looksLikeTimeoutError(Object error) => OdbcErrorInspector.isTimeout(error);

  /// Gets or creates a circuit breaker for the given connection string.
  ConnectionCircuitBreaker _getCircuitBreaker(String connectionString) {
    return _circuitBreakers.getOrCreate(connectionString);
  }

  /// Ensures ODBC environment is initialized before operations.
  ///
  /// Concurrent callers share a single in-flight initialization future so the
  /// underlying `OdbcService.initialize()` runs at most once. The memoized
  /// future is cleared on failure so a later request can retry.
  Future<Result<void>> _ensureInitialized() {
    if (_initialized) {
      return Future<Result<void>>.value(const Success(unit));
    }
    return _initialization ??= _initializeOnce();
  }

  Future<Result<void>> _initializeOnce() async {
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
        _initialization = null;
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
              'reason': OdbcContextConstants.odbcInitializationFailedReason,
              'user_message': 'Não foi possível inicializar o ambiente ODBC neste computador.',
            },
          ),
        );
      },
    );
  }

  Future<Result<Config>> _resolveConfigForQuery(String? configId) {
    return _configSource.resolveConfigForQuery(configId);
  }

  Future<Result<Config>> _resolveActiveConfig() {
    return _configSource.resolveActiveConfig();
  }

  String _odbcErrorMessage(Object error) => OdbcErrorInspector.message(error);

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
        options: _optionsResolver.defaultOptions.toOdbcConnectionOptions(),
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
        final configResult = await _resolveConfigForQuery(request.configId);

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
            domain.ConfigurationFailure.withContext(
              message: 'Failed to load database configuration',
              cause: domainFailure,
              context: {
                'reason': OdbcContextConstants.configurationLoadFailedReason,
                'operation': 'resolve_config_for_query',
                if (request.configId != null) 'config_id': request.configId,
              },
            ),
          ),
        );
      },
      (error) => Failure(
        OdbcFailureMapper.mapConnectionError(
          error,
          operation: 'initialize_odbc',
          context: {
            'reason': OdbcContextConstants.odbcInitializationFailedReason,
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
              'reason': OdbcContextConstants.stageBudgetExhaustedReason(stage),
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
              'reason': OdbcContextConstants.stageRetryFailedReason(stage),
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

    final baseOptions = _optionsResolver.forTimeout(timeout);
      final hintedOptions = _optionsResolver.hintedFor(
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
      allowNativeCompatibleAcquire: _nativeCompatiblePolicy.shouldUseAcquire(
        databaseType: databaseConfig.databaseType,
        request: request,
        preparedExecution: preparedExecution,
        acquireOptions: null,
        timeout: timeout,
        defaultQueryTimeout: ConnectionConstants.defaultQueryTimeout,
        connectionString: connectionString,
      ),
    );
  }

  Future<Result<QueryResponse>> _executeQueryWithPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    required Duration? timeout,
    ConnectionAcquireOptions? acquireOptions,
    bool allowAdaptiveRetry = true,
    bool allowNativeCompatibleAcquire = false,
    DateTime? deadline,
  }) async {
    final effectiveDeadline = deadline ?? _deadlineFor(timeout);
    final poolAcquireOptions =
        acquireOptions ??
        _optionsResolver.forTimeout(
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
      final outcome = await _queryRunner.runWithTimeout(
        connId: connId,
        request: request,
        preparedExecution: preparedExecution,
        connectionString: connectionString,
        timeout: _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        executionMode: allowNativeCompatibleAcquire ? 'native_compatible' : 'pooled',
      );

      if (outcome.isSuccess &&
          allowNativeCompatibleAcquire &&
          timeout != null &&
          timeout > Duration.zero) {
        _nativeCompatiblePolicy.rememberNativeCompatibleTimeout(
          connectionString: connectionString,
          timeout: timeout,
        );
      }

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
          _metrics.recordOdbcInvalidConnectionRecycle();
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

        if (allowAdaptiveRetry && _optionsResolver.isBufferTooSmallError(error)) {
          _metrics.recordOdbcBufferExpansion();
          _metrics.recordDiagnosticReason(
            category: 'query',
            reason: OdbcContextConstants.bufferTooSmallReason,
          );
          _connectionManager.recordPooledExecutionFailure(
            connectionString: connectionString,
            connectionId: connId,
            error: error,
            stage: 'query',
          );
          final currentBufferBytes =
              effectiveOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes;
          _optionsResolver.rememberExpandedBuffer(
            connectionString: connectionString,
            sql: preparedExecution.sql,
            currentBufferBytes: currentBufferBytes,
            error: error,
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
            acquireOptions: _optionsResolver.expandedFor(
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
            'reason': RpcSqlBudgetConstants.queryTimeoutReason,
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

  bool _shouldFallbackTransactionalNativePoolToDirect(
    _BatchExecutionContext context,
    Object error,
    int attempt,
  ) {
    if (!context.nativeCompatibleAcquire || context.ownedConnection || attempt > 0) {
      return false;
    }
    final failure = error is domain.Failure ? error : OdbcFailureMapper.mapQueryError(error);
    if (failure.context['operation'] == 'transaction_validation') {
      return false;
    }
    return failure is domain.ConnectionFailure ||
        _queryFailureIndicatesInvalidConnectionId(failure) ||
        failure.context['connectionFailed'] == true ||
        failure.context['timeout'] == true ||
        failure.context['reason'] == OdbcContextConstants.bufferTooSmallReason ||
        failure.context['reason'] == OdbcContextConstants.odbcWorkerBusyConnectReason ||
        OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(_odbcErrorMessage(failure));
  }

  void _recordTransactionalNativePoolFallback({
    required _BatchExecutionContext context,
    required Object error,
    required String stage,
    String? connectionId,
  }) {
    _metrics.recordTransactionalBatchNativePoolFallback();
    _metrics.recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.transactionalNativePoolFallbackReason,
    );
    if (connectionId != null) {
      _connectionManager.markConnectionForDiscard(connectionId);
    }
    _connectionManager.recordPooledExecutionFailure(
      connectionString: context.connectionString,
      connectionId: connectionId,
      error: error,
      stage: stage,
    );
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
    final bulkInsertPlan = await _tryHomogeneousInsertBatchAutoRoutePlan(commands);
    if (bulkInsertPlan != null) {
      return _executeHomogeneousInsertBatchAsBulk(
        commands: commands,
        plan: bulkInsertPlan,
        database: database,
        options: options,
        timeout: effectiveTimeout,
        sourceRpcRequestId: sourceRpcRequestId,
        batchSqlPreview: batchPreview,
      );
    }
    if (HomogeneousInsertBatchPlanner.shouldRecommend(commands)) {
      _recordBulkInsertRecommendation(commands);
    }
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

    var forceDirectTransactionalConnection = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      final contextResult = await _prepareBatchExecutionContext(
        database: database,
        timeout: effectiveTimeout,
        useOwnedConnection: options.transaction && forceDirectTransactionalConnection,
        allowNativeCompatibleTransaction: options.transaction && !forceDirectTransactionalConnection,
        commands: commands,
        batchSqlPreview: batchPreview,
        sourceRpcRequestId: sourceRpcRequestId,
      );
      if (contextResult.isError()) {
        return Failure(contextResult.exceptionOrNull()!);
      }

      final context = contextResult.getOrNull()!;
      final connectionState = _BatchConnectionState(context.connectionId);
      var recycleAfterRelease = false;
      BatchTransactionGuard? transaction;
      try {
        final batchAccessMode = _inferBatchAccessMode(commands);
        final beginResult = await _txManager.beginIfNeeded(
          connectionId: connectionState.connectionId!,
          transactionEnabled: options.transaction,
          lockTimeout: _transactionLockTimeout(
            options: options,
            timeout: effectiveTimeout,
          ),
          accessMode: batchAccessMode,
        );
        if (beginResult.isError()) {
          final beginFailure = beginResult.exceptionOrNull()! as domain.Failure;
          if (_shouldFallbackTransactionalNativePoolToDirect(context, beginFailure, attempt)) {
            _recordTransactionalNativePoolFallback(
              context: context,
              connectionId: connectionState.connectionId,
              error: beginFailure,
              stage: 'transaction_begin',
            );
            forceDirectTransactionalConnection = true;
            recycleAfterRelease = true;
          } else if (options.transaction && attempt == 0 && _queryFailureIndicatesInvalidConnectionId(beginFailure)) {
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
          } else if (options.transaction && context.nativeCompatibleAcquire) {
            _metrics.recordTransactionalBatchNativePoolPath();
            developer.log(
              'Transactional executeBatch uses native-compatible ODBC pool path',
              name: 'database_gateway',
              level: 800,
            );
          }
          transaction = BatchTransactionGuard(beginResult.getOrNull()!.transactionId);

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
            final commandFailure = commandResult.exceptionOrNull()!;
            if (_shouldFallbackTransactionalNativePoolToDirect(context, commandFailure, attempt)) {
              _recordTransactionalNativePoolFallback(
                context: context,
                connectionId: connectionState.connectionId,
                error: commandFailure,
                stage: 'transaction_execute',
              );
              forceDirectTransactionalConnection = true;
              recycleAfterRelease = true;
              continue;
            }
            return Failure(commandResult.exceptionOrNull()!);
          }

          if (options.transaction && transaction.isActive) {
            _maybeRecordTransactionalBatchDeadlineNearStall(
              deadline: context.deadline,
              effectiveTimeout: effectiveTimeout,
              commandCount: commands.length,
            );
            final commitResult = await _txManager.commit(
              connectionId: connectionState.connectionId!,
              guard: transaction,
              deadline: context.deadline,
            );
            if (commitResult.isError()) {
              // Commit failure may leave an ambiguous engine state even after
              // rollback; do not re-run the batch on another connection path.
              return Failure(commitResult.exceptionOrNull()!);
            }
          }

          return commandResult;
        }
      } on Object catch (error, stackTrace) {
        final activeConnectionId = connectionState.connectionId;
        if (options.transaction) {
          final rollbackTimeout = _txManager.rollbackTimeoutFromDeadline(context.deadline);
          await transaction?.rollback(
            (transactionId) async {
              if (activeConnectionId == null) {
                return;
              }
              await _txManager.rollbackIfNeeded(
                activeConnectionId,
                transactionId,
                timeout: rollbackTimeout,
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
        if (_shouldFallbackTransactionalNativePoolToDirect(context, error, attempt)) {
          _recordTransactionalNativePoolFallback(
            context: context,
            connectionId: activeConnectionId,
            error: error,
            stage: 'transaction_unexpected_error',
          );
          forceDirectTransactionalConnection = true;
          recycleAfterRelease = true;
          continue;
        }
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Batch execution failed unexpectedly',
            cause: error,
            context: {
              'reason': OdbcContextConstants.transactionFailedReason,
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
              nativeCompatibleAcquire: context.nativeCompatibleAcquire,
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
          'reason': OdbcContextConstants.transactionFailedReason,
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

  Future<HomogeneousInsertBatchPlan?> _tryHomogeneousInsertBatchAutoRoutePlan(
    List<SqlCommand> commands,
  ) async {
    if (commands.length < ConnectionConstants.batchBulkInsertRouteThreshold) {
      return null;
    }

    final configResult = await _resolveActiveConfig();
    if (configResult.isError()) {
      return null;
    }

    final databaseType = _buildDatabaseConfig(configResult.getOrThrow()).databaseType;
    if (!HomogeneousInsertBatchPlanner.supportsAutoRoute(databaseType)) {
      return null;
    }

    return HomogeneousInsertBatchPlanner.tryPlan(commands);
  }

  void _recordBulkInsertRecommendation(List<SqlCommand> commands) {
    _metrics.recordBatchBulkInsertRecommended();
    developer.log(
      'Large homogeneous INSERT batch detected; sql.bulkInsert is recommended for this workload',
      name: 'database_gateway',
      level: 800,
      error: {
        'command_count': commands.length,
        'table': commands.isEmpty ? null : HomogeneousInsertBatchPlanner.tryPlan(commands)?.request.table,
        'threshold': ConnectionConstants.batchBulkInsertRecommendationThreshold,
      },
    );
  }

  Future<Result<List<SqlCommandResult>>> _executeHomogeneousInsertBatchAsBulk({
    required List<SqlCommand> commands,
    required HomogeneousInsertBatchPlan plan,
    required String? database,
    required SqlExecutionOptions options,
    required Duration? timeout,
    required String batchSqlPreview,
    String? sourceRpcRequestId,
  }) async {
    final validationFailure = OdbcBulkInsertExecutor.validate(plan.request);
    if (validationFailure != null) {
      return Failure(validationFailure);
    }

    _metrics.recordBatchBulkInsertRouted();
    developer.log(
      'Routing homogeneous INSERT batch to native bulk-insert path',
      name: 'database_gateway',
      level: 800,
      error: {
        'command_count': commands.length,
        'table': plan.request.table,
        'row_count': plan.request.rowCount,
        'transaction': options.transaction,
        'threshold': ConnectionConstants.batchBulkInsertRouteThreshold,
      },
    );

    if (!options.transaction) {
      final bulkResult = await executeBulkInsert(
        plan.request,
        timeout: timeout,
        database: database,
      );
      return bulkResult.fold(
        (_) => Success(_syntheticBulkInsertBatchResults(commands)),
        Failure.new,
      );
    }

    var forceDirectTransactionalConnection = false;
    for (var attempt = 0; attempt < 2; attempt++) {
      final contextResult = await _prepareBatchExecutionContext(
        database: database,
        timeout: timeout,
        useOwnedConnection: forceDirectTransactionalConnection,
        allowNativeCompatibleTransaction: !forceDirectTransactionalConnection,
        commands: commands,
        batchSqlPreview: batchSqlPreview,
        sourceRpcRequestId: sourceRpcRequestId,
      );
      if (contextResult.isError()) {
        return Failure(contextResult.exceptionOrNull()!);
      }

      final context = contextResult.getOrThrow();
      final connectionState = _BatchConnectionState(context.connectionId);
      var recycleAfterRelease = false;
      BatchTransactionGuard? transaction;
      try {
        final beginResult = await _txManager.beginIfNeeded(
          connectionId: connectionState.connectionId!,
          transactionEnabled: true,
          lockTimeout: _transactionLockTimeout(
            options: options,
            timeout: timeout,
          ),
          accessMode: TransactionAccessMode.readWrite,
        );
        if (beginResult.isError()) {
          final beginFailure = beginResult.exceptionOrNull()! as domain.Failure;
          if (_shouldFallbackTransactionalNativePoolToDirect(context, beginFailure, attempt)) {
            _recordTransactionalNativePoolFallback(
              context: context,
              connectionId: connectionState.connectionId,
              error: beginFailure,
              stage: 'transaction_begin',
            );
            forceDirectTransactionalConnection = true;
            recycleAfterRelease = true;
          } else {
            return Failure(beginFailure);
          }
        } else {
          transaction = BatchTransactionGuard(beginResult.getOrNull()!.transactionId);
          final bulkResult = await _bulkInsertExecutor.executeOnConnection(
            connectionId: connectionState.connectionId!,
            request: plan.request,
            timeout: _remainingTimeout(context.deadline) ?? timeout,
            deadline: context.deadline,
          );
          if (bulkResult.isError()) {
            final bulkFailure = bulkResult.exceptionOrNull()!;
            if (_shouldFallbackTransactionalNativePoolToDirect(context, bulkFailure, attempt)) {
              _recordTransactionalNativePoolFallback(
                context: context,
                connectionId: connectionState.connectionId,
                error: bulkFailure,
                stage: 'transaction_execute',
              );
              forceDirectTransactionalConnection = true;
              recycleAfterRelease = true;
              continue;
            }
            return Failure(bulkFailure);
          }

          if (transaction.isActive) {
            final commitResult = await _txManager.commit(
              connectionId: connectionState.connectionId!,
              guard: transaction,
              deadline: context.deadline,
            );
            if (commitResult.isError()) {
              return Failure(commitResult.exceptionOrNull()!);
            }
          }

          return Success(_syntheticBulkInsertBatchResults(commands));
        }
      } on Object catch (error, stackTrace) {
        final activeConnectionId = connectionState.connectionId;
        final rollbackTimeout = _txManager.rollbackTimeoutFromDeadline(context.deadline);
        await transaction?.rollback(
          (transactionId) async {
            if (activeConnectionId == null) {
              return;
            }
            await _txManager.rollbackIfNeeded(
              activeConnectionId,
              transactionId,
              timeout: rollbackTimeout,
            );
          },
        );
        developer.log(
          'Unexpected failure during bulk-insert batch execution',
          name: 'database_gateway',
          level: 1000,
          error: error,
          stackTrace: stackTrace,
        );
        if (_shouldFallbackTransactionalNativePoolToDirect(context, error, attempt)) {
          _recordTransactionalNativePoolFallback(
            context: context,
            connectionId: activeConnectionId,
            error: error,
            stage: 'transaction_unexpected_error',
          );
          forceDirectTransactionalConnection = true;
          recycleAfterRelease = true;
          continue;
        }
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Bulk-insert batch execution failed unexpectedly',
            cause: error,
            context: {
              'reason': OdbcContextConstants.transactionFailedReason,
              'operation': 'bulk_insert_batch_unexpected_error',
              'transaction': true,
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
              nativeCompatibleAcquire: context.nativeCompatibleAcquire,
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
        message: 'Bulk-insert batch transaction failed after retry',
        context: {
          'reason': OdbcContextConstants.transactionFailedReason,
          'operation': 'bulk_insert_batch_transaction',
        },
      ),
    );
  }

  List<SqlCommandResult> _syntheticBulkInsertBatchResults(List<SqlCommand> commands) {
    return List<SqlCommandResult>.generate(
      commands.length,
      (index) => SqlCommandResult.success(
        index: index,
        rows: const [],
        affectedRows: 1,
      ),
      growable: false,
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

    final configResult = await _resolveActiveConfig();
    if (configResult.isError()) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to load database configuration for read-only batch execution',
          cause: configResult.exceptionOrNull(),
          context: {
            'reason': OdbcContextConstants.configurationLoadFailedReason,
            'operation': 'resolve_active_config_read_only_batch',
          },
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
    final safePoolParallelism = _safeReadOnlyBatchParallelism(_settings.poolSize);
    _readOnlyBatchParallelSemaphore.resize(safePoolParallelism);

    return _readOnlyBatchParallelExecutor.execute(
      agentId: agentId,
      commands: commands,
      connectionString: connectionString,
      databaseConfig: localConfig,
      options: options,
      timeout: timeout,
      batchSqlPreview: batchSqlPreview,
      poolSize: _settings.poolSize,
      sourceRpcRequestId: sourceRpcRequestId,
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
    required bool allowNativeCompatibleTransaction,
    required List<SqlCommand> commands,
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

    final configResult = await _resolveActiveConfig();
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
    final useNativeCompatibleTransaction =
        allowNativeCompatibleTransaction &&
        _nativeCompatiblePolicy.shouldUseTransactionalBatch(
          databaseType: localConfig.databaseType,
          commands: commands,
        );

    final isTransactional = useOwnedConnection || allowNativeCompatibleTransaction;
    if (useOwnedConnection || (allowNativeCompatibleTransaction && !useNativeCompatibleTransaction)) {
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
      final remainingTimeout = _remainingTimeoutFromDeadline(deadline) ?? timeout;
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: isTransactional
            ? _optionsResolver.transactionalForTimeout(remainingTimeout).toOdbcConnectionOptions()
            : _optionsResolver.forTimeout(remainingTimeout).toOdbcConnectionOptions(),
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

    final remainingTimeout = _remainingTimeoutFromDeadline(deadline) ?? timeout;
    final connectionOptions = isTransactional
        ? _optionsResolver.transactionalForTimeout(remainingTimeout)
        : _optionsResolver.forTimeout(remainingTimeout);
    final poolResult = useNativeCompatibleTransaction
        ? await _connectionManager.acquireNativeCompatiblePooledConnection(
            connectionString,
            leaseFallbackOptions: connectionOptions,
            deadline: deadline,
            context: {'operation': 'batch_transaction_native_compatible'},
          )
        : await _connectionManager.acquirePooledConnection(
            connectionString,
            options: connectionOptions,
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
        nativeCompatibleAcquire: useNativeCompatibleTransaction,
      ),
    );
  }

  /// Infers the safest `TransactionAccessMode` for a batch.
  ///
  /// When every command in the batch passes the same `SELECT`/`WITH` shape
  /// check used by the read-only batch dispatch path, the engine can be told
  /// the unit of work is read-only. PostgreSQL / MySQL / MariaDB / DB2 /
  /// Oracle then skip locking, pick snapshot reads where applicable, and
  /// short-circuit lock acquisition — reducing the chance of leaving tables
  /// locked when a long-running query is rolled back. Engines without a
  /// native hint (SQL Server, SQLite, Snowflake) silently no-op.
  ///
  /// Returns [TransactionAccessMode.readWrite] when the batch is empty or
  /// contains any non-`SELECT` command, preserving previous behavior for
  /// mixed and write-only batches.
  TransactionAccessMode _inferBatchAccessMode(List<SqlCommand> commands) {
    if (commands.isEmpty) {
      return TransactionAccessMode.readWrite;
    }
    for (final command in commands) {
      if (SqlValidator.validateSelectQuery(command.sql).isError()) {
        return TransactionAccessMode.readWrite;
      }
    }
    _metrics.recordTransactionalBatchReadOnlyInference();
    return TransactionAccessMode.readOnly;
  }

  /// Records observability when a transactional batch reaches commit having
  /// already consumed at least 80% of its active deadline.
  ///
  /// A transaction this close to the timeout is at risk of being aborted
  /// mid-commit, which forces the rollback path to run with even less time
  /// and can leave engine-side locks while cleanup completes. The signal
  /// lets dashboards correlate the symptom (locks lingering) with the cause
  /// (transactions running near their budget) before users notice.
  void _maybeRecordTransactionalBatchDeadlineNearStall({
    required DateTime? deadline,
    required Duration? effectiveTimeout,
    required int commandCount,
  }) {
    if (deadline == null || effectiveTimeout == null || effectiveTimeout <= Duration.zero) {
      return;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      // Already past the deadline; the commit/rollback path handles the
      // failure surface. No additional signal needed here.
      return;
    }
    final budgetMicros = effectiveTimeout.inMicroseconds;
    if (budgetMicros <= 0) {
      return;
    }
    final consumedRatio = 1 - (remaining.inMicroseconds / budgetMicros);
    if (consumedRatio < 0.8) {
      return;
    }
    _metrics.recordTransactionalBatchDeadlineNearStall();
    developer.log(
      'Transactional batch reached commit near deadline',
      name: 'database_gateway',
      level: 900,
      error: <String, Object?>{
        'consumed_ratio': consumedRatio,
        'remaining_ms': remaining.inMilliseconds,
        'effective_timeout_ms': effectiveTimeout.inMilliseconds,
        'command_count': commandCount,
        'suggestion':
            'Increase SqlExecutionOptions.timeoutMs or split the batch '
            'to avoid locks lingering through the rollback window.',
      },
    );
  }


  Future<Result<List<SqlCommandResult>>> _executeBatchCommands({
    required _BatchExecutionContext context,
    required _BatchConnectionState connectionState,
    required String agentId,
    required List<SqlCommand> commands,
    required SqlExecutionOptions options,
    required BatchTransactionGuard transaction,
    String? sourceRpcRequestId,
  }) async {
    final results = <SqlCommandResult>[];
    final repeatedPreparedKeys = OdbcQueryRunner.collectRepeatedPreparedKeys(commands);
    final preparedStatements = <String, int>{};

    try {
      for (var i = 0; i < commands.length; i++) {
        final command = commands[i];
        final validation = SqlValidator.validateSqlForExecution(command.sql);
        if (validation.isError()) {
          final failure = validation.exceptionOrNull()! as domain.Failure;
          if (options.transaction) {
            final rollbackTimeout = _txManager.rollbackTimeoutFromDeadline(context.deadline);
            await transaction.rollback(
              (transactionId) => _txManager.rollbackIfNeeded(
                context.connectionId,
                transactionId,
                timeout: rollbackTimeout,
              ),
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Transaction aborted due to command validation failure',
                cause: failure,
                context: {
                  'reason': OdbcContextConstants.transactionFailedReason,
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

        Future<QueryExecutionOutcome> executeCurrentCommand() async {
          final currentConnectionId = connectionState.connectionId;
          if (currentConnectionId == null) {
            return QueryExecutionOutcome.failure(
              StateError('batch_connection_unavailable'),
            );
          }

          final key = OdbcQueryRunner.preparedStatementKeyFor(preparedExecution);
          final usePrepared = repeatedPreparedKeys.contains(key);
          return usePrepared
              ? _queryRunner.runPreparedBatch(
                  connectionId: currentConnectionId,
                  request: commandRequest,
                  preparedExecution: preparedExecution,
                  preparedStatements: preparedStatements,
                  statementKey: key,
                  timeout: remainingTimeout,
                )
              : _queryRunner.runWithTimeout(
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
              final rollbackTimeout = _txManager.rollbackTimeoutFromDeadline(context.deadline);
              await transaction.rollback(
                (transactionId) async {
                  final activeConnId = connectionState.connectionId;
                  if (activeConnId == null) return;
                  await _txManager.rollbackIfNeeded(
                    activeConnId,
                    transactionId,
                    timeout: rollbackTimeout,
                  );
                },
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
                    'reason': OdbcContextConstants.transactionFailedReason,
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
            final rollbackTimeout = _txManager.rollbackTimeoutFromDeadline(context.deadline);
            await transaction.rollback(
              (transactionId) async {
                final activeConnId = connectionState.connectionId;
                if (activeConnId == null) return;
                await _txManager.rollbackIfNeeded(
                  activeConnId,
                  transactionId,
                  timeout: rollbackTimeout,
                );
              },
            );
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Transaction aborted due to timeout',
                cause: error,
                context: {
                  'reason': OdbcContextConstants.transactionFailedReason,
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
                'reason': RpcSqlBudgetConstants.queryTimeoutReason,
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
        await _statementExecutor.closePreparedStatements(
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

  Future<QueryExecutionOutcome> _retryBatchCommandAfterConnectionFailure({
    required _BatchExecutionContext context,
    required _BatchConnectionState connectionState,
    required Map<String, int> preparedStatements,
    required domain.Failure failure,
    required Future<QueryExecutionOutcome> Function() executeCommand,
  }) async {
    final currentConnectionId = connectionState.connectionId;
    if (currentConnectionId == null) {
      return QueryExecutionOutcome.failure(failure);
    }

    if (preparedStatements.isNotEmpty) {
      await _statementExecutor.closePreparedStatements(
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
      options: _optionsResolver.forTimeout(
        _remainingTimeoutFromDeadline(context.deadline),
      ),
      deadline: context.deadline,
      context: {'operation': 'batch_reacquire_connection'},
    );
    if (reacquireResult.isError()) {
      return QueryExecutionOutcome.failure(
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
        final configResult = await _resolveActiveConfig();

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

  @override
  Future<Result<int>> executeBulkInsert(
    BulkInsertRequest request, {
    Duration? timeout,
    String? database,
  }) async {
    final validationFailure = OdbcBulkInsertExecutor.validate(request);
    if (validationFailure != null) {
      return Failure(validationFailure);
    }

    final initResult = await _ensureInitialized();
    return initResult.fold(
      (_) async {
        final configResult = await _resolveActiveConfig();
        return configResult.fold(
          (config) async {
            final localConfig = _buildDatabaseConfig(config);
            final connectionString = _resolveConnectionString(
              config,
              localConfig,
              databaseOverride: database,
            );
            return _bulkInsertExecutor.executeDirect(
              request,
              connectionString,
              timeout: timeout,
              databaseType: localConfig.databaseType,
            );
          },
          (domainFailure) => Failure(
            domain.ConfigurationFailure.withContext(
              message: 'Failed to load database configuration for bulk insert',
              cause: domainFailure,
              context: {
                'reason': OdbcContextConstants.configurationLoadFailedReason,
                'operation': 'resolve_active_config_bulk_insert',
              },
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
      options: _optionsResolver.forTimeout(timeout),
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
          _metrics.recordOdbcInvalidConnectionRecycle();
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
            'reason': RpcSqlBudgetConstants.queryTimeoutReason,
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
        final asyncResult = await _statementExecutor.runNativeAsyncQueryWithTimeout(
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
      final statementKey = OdbcQueryRunner.preparedStatementKeyFor(preparedExecution);
      try {
        final stmtId = await _statementExecutor.getOrPrepareStatement(
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

        return await _statementExecutor.executePreparedStatementWithTimeout(
          connectionId: connectionId,
          preparedExecution: preparedExecution,
          statementId: stmtId.getOrThrow(),
          timeout: timeout,
        );
      } finally {
        await _statementExecutor.closePreparedStatements(
          connectionId,
          preparedStatements.values,
        );
      }
    } on TimeoutException catch (error) {
      _metrics.recordQueryTimeout();
      _metrics.recordOdbcQueryTimeoutByStage('non_query');
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: RpcSqlBudgetConstants.queryTimeoutReason,
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

  Future<Result<QueryResponse>> _executeQueryWithoutPool(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    ConnectionAcquireOptions? options,
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
        _optionsResolver.forTimeout(
          _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        );

    try {
      final connectResult = await _connectionManager.connectSafely(
        connectionString,
        options: effectiveOptions.toOdbcConnectionOptions(),
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
            final outcome = await _queryRunner.runWithTimeout(
              connId: connection.id,
              request: request,
              preparedExecution: preparedExecution,
              connectionString: connectionString,
              timeout: _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
              executionMode: 'direct',
            );
            if (!outcome.isSuccess) {
              final error = outcome.error!;
              if (_optionsResolver.isBufferTooSmallError(error)) {
                _metrics.recordOdbcBufferExpansion();
                _metrics.recordDiagnosticReason(
                  category: 'query',
                  reason: OdbcContextConstants.bufferTooSmallReason,
                );
                final currentBufferBytes =
                    effectiveOptions.maxResultBufferBytes ?? ConnectionConstants.defaultMaxResultBufferBytes;
                _optionsResolver.rememberExpandedBuffer(
                  connectionString: connectionString,
                  sql: preparedExecution.sql,
                  currentBufferBytes: currentBufferBytes,
                  error: error,
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
                    options: _optionsResolver.expandedFor(
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
                  'reason': RpcSqlBudgetConstants.queryTimeoutReason,
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
        options: _optionsResolver.forTimeout(
          _remainingTimeoutFromDeadline(effectiveDeadline) ?? timeout,
        ).toOdbcConnectionOptions(),
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
                  'reason': RpcSqlBudgetConstants.queryTimeoutReason,
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
    return OdbcConnectionStringRewriter.resolve(
      config,
      databaseConfig,
      databaseOverride: databaseOverride,
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

  /// Maps a driver name string from the persisted [Config] to the local
  /// [DatabaseType] used by SQL builders (paging, boolean literals, etc.).
  ///
  /// Falls back to the richer `odbc_fast` `DatabaseType.fromDriverName`
  /// heuristic to recognise variants the previous exact-match switch missed
  /// (`Microsoft SQL Server`, `Adaptive Server Anywhere`, `PostgreSQL Unicode`,
  /// etc.). When the underlying driver maps to an engine outside the three
  /// dialects the local SQL builders support, the call still returns
  /// [DatabaseType.sqlServer] for backwards compatibility, but emits a
  /// structured warning so the misconfiguration is observable instead of
  /// silently producing broken SQL.
  /// Test-only entry point for [_mapDriverNameToDatabaseType] so the
  /// heuristic and fallback warning can be exercised without standing up
  /// the full gateway harness.
  @visibleForTesting
  DatabaseType mapDriverNameToDatabaseTypeForTesting(String driverName) {
    return _mapDriverNameToDatabaseType(driverName);
  }

  DatabaseType _mapDriverNameToDatabaseType(String driverName) {
    final exact = switch (driverName) {
      'SQL Server' => DatabaseType.sqlServer,
      'PostgreSQL' => DatabaseType.postgresql,
      'SQL Anywhere' => DatabaseType.sybaseAnywhere,
      _ => null,
    };
    if (exact != null) {
      return exact;
    }

    final detected = odbc.DatabaseType.fromDriverName(driverName);
    final mapped = switch (detected) {
      odbc.DatabaseType.sqlServer => DatabaseType.sqlServer,
      odbc.DatabaseType.postgresql => DatabaseType.postgresql,
      odbc.DatabaseType.sybaseAsa => DatabaseType.sybaseAnywhere,
      _ => null,
    };
    if (mapped != null) {
      return mapped;
    }

    developer.log(
      'Unsupported ODBC driver detected; falling back to sqlServer dialect. '
      'SQL generation may produce incorrect statements for this engine.',
      name: 'database_gateway',
      level: 1000,
      error: <String, Object?>{
        'driver_name': driverName,
        'detected_engine': detected.name,
        'supported_dialects': <String>['sqlServer', 'postgresql', 'sybaseAnywhere'],
      },
    );
    return DatabaseType.sqlServer;
  }

}
