import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:odbc_fast/odbc_fast.dart' as odbc show DatabaseType;
import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_circuit_breaker.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_query_config_source.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_orchestrator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_rewriter.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_investigation_recorder.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_retry_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_abort_service.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_non_query_execution_orchestrator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_orchestrator.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/adaptive_odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// ODBC Database Gateway using odbc_fast package.
///
/// This implementation provides:
/// - Native Rust engine for better performance
/// - Async API (non-blocking) for Flutter
/// - Simplified code (no manual column extraction)
/// - Built-in error handling with Result types
/// - Connection pooling for reduced overhead
/// - Performance metrics collection
class OdbcDatabaseGateway implements IDatabaseGateway, IPoolDiscardInflightDiagnostics, IOdbcConnectionCircuitBreaker {
  OdbcDatabaseGateway(
    this._configSource,
    this._service,
    IConnectionPool connectionPool,
    IRetryManager retryManager,
    this._metrics,
    this._settings, {
    FeatureFlags? featureFlags,
    DirectOdbcConnectionLimiter? directConnectionLimiter,
    ISqlInvestigationCollector? sqlInvestigation,
    OdbcInFlightExecutionRegistry? inFlightExecutionRegistry,
  }) : _inFlightRegistry = inFlightExecutionRegistry ?? OdbcInFlightExecutionRegistry(),
       _retryCoordinator = OdbcGatewayRetryCoordinator(retryManager),
       _investigationRecorder = OdbcGatewayInvestigationRecorder(
         featureFlags: featureFlags,
         sqlInvestigation: sqlInvestigation,
       ),
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
       _nativeCompatiblePolicy = NativeCompatibleAcquirePolicy(featureFlags: featureFlags),
       _optionsResolver = OdbcConnectionOptionsResolver(_settings),
       _resultEncodingExecutor = OdbcResultEncodingExecutor(
         _service,
         usageProfile: resolveOdbcUsageProfile(),
       ),
       _uuid = const Uuid() {
    _txManager = OdbcBatchTransactionManager(
      service: _service,
      metrics: _metrics,
      onRollbackUnconfirmed: _connectionManager.markConnectionForDiscard,
    );
    _statementExecutor = OdbcStatementExecutor(
      service: _service,
      metrics: _metrics,
      markConnectionForDiscard: _connectionManager.markConnectionForDiscard,
    );
    _queryRunner = OdbcQueryRunner(
      queries: _service,
      metrics: _metrics,
      statementExecutor: _statementExecutor,
      resultEncodingExecutor: _resultEncodingExecutor,
      markConnectionForDiscard: _connectionManager.markConnectionForDiscard,
      inFlightRegistry: _inFlightRegistry,
    );
    _inFlightAbortService = OdbcInFlightExecutionAbortService(
      registry: _inFlightRegistry,
      statementExecutor: _statementExecutor,
      markConnectionForDiscard: _connectionManager.markConnectionForDiscard,
    );
    _queryExecutionOrchestrator = OdbcQueryExecutionOrchestrator(
      connectionManager: _connectionManager,
      queryRunner: _queryRunner,
      optionsResolver: _optionsResolver,
      nativeCompatiblePolicy: _nativeCompatiblePolicy,
      metrics: _metrics,
      featureFlags: featureFlags,
      sqlInvestigation: sqlInvestigation,
    );
    _bulkInsertExecutor = OdbcBulkInsertExecutor(
      connectionManager: _connectionManager,
      optionsResolver: _optionsResolver,
      service: _service,
      metrics: _metrics,
      settings: _settings,
      parallelPool: connectionPool is AdaptiveOdbcConnectionPool ? connectionPool.nativeBulkInsertPool : null,
      inFlightRegistry: _inFlightRegistry,
    );
    _readOnlyBatchParallelExecutor = OdbcReadOnlyBatchParallelExecutor(
      connectionManager: _connectionManager,
      queryRunner: _queryRunner,
      optionsResolver: _optionsResolver,
      metrics: _metrics,
      parallelSemaphore: _readOnlyBatchParallelSemaphore,
      uuid: _uuid,
      recordInfrastructureFailure: _investigationRecorder.recordBatchInfrastructureFailure,
    );
    _batchExecutionOrchestrator = OdbcBatchExecutionOrchestrator(
      connectionManager: _connectionManager,
      txManager: _txManager,
      bulkInsertExecutor: _bulkInsertExecutor,
      queryRunner: _queryRunner,
      statementExecutor: _statementExecutor,
      optionsResolver: _optionsResolver,
      nativeCompatiblePolicy: _nativeCompatiblePolicy,
      metrics: _metrics,
      readOnlyBatchParallelExecutor: _readOnlyBatchParallelExecutor,
      readOnlyBatchParallelSemaphore: _readOnlyBatchParallelSemaphore,
      uuid: _uuid,
      poolSize: _settings.poolSize,
      ensureInitialized: _ensureInitialized,
      resolveActiveConfig: _resolveActiveConfig,
      buildDatabaseConfig: _buildDatabaseConfig,
      resolveConnectionString: _resolveConnectionString,
      recordInfrastructureFailure: _investigationRecorder.recordBatchInfrastructureFailure,
      recordExecutionFailure: _investigationRecorder.recordExecutionFailure,
    );
    _nonQueryExecutionOrchestrator = OdbcNonQueryExecutionOrchestrator(
      connectionManager: _connectionManager,
      service: _service,
      statementExecutor: _statementExecutor,
      optionsResolver: _optionsResolver,
      metrics: _metrics,
      inFlightRegistry: _inFlightRegistry,
    );
  }

  @override
  int get poolDiscardInflightCount => _connectionManager.poolDiscardInflightCount;

  /// Port for aborting registered in-flight ODBC executions (ghost-query path).
  ISqlInFlightExecutionAbortPort get inFlightAbortPort => _inFlightAbortService;

  final OdbcInFlightExecutionRegistry _inFlightRegistry;
  late final OdbcInFlightExecutionAbortService _inFlightAbortService;

  @override
  Future<void> reconcilePoolDiscardInflight() => _connectionManager.reconcilePoolDiscardInflight();

  final OdbcService _service;
  final IQueryConfigSource _configSource;
  final MetricsCollector _metrics;
  final IOdbcConnectionSettings _settings;
  final OdbcGatewayRetryCoordinator _retryCoordinator;
  final OdbcGatewayInvestigationRecorder _investigationRecorder;
  final OdbcGatewayConnectionManager _connectionManager;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final OdbcResultEncodingExecutor _resultEncodingExecutor;
  late final OdbcBatchTransactionManager _txManager;
  late final OdbcStatementExecutor _statementExecutor;
  late final OdbcQueryRunner _queryRunner;
  late final OdbcQueryExecutionOrchestrator _queryExecutionOrchestrator;
  late final OdbcBulkInsertExecutor _bulkInsertExecutor;
  late final OdbcReadOnlyBatchParallelExecutor _readOnlyBatchParallelExecutor;
  late final OdbcBatchExecutionOrchestrator _batchExecutionOrchestrator;
  late final OdbcNonQueryExecutionOrchestrator _nonQueryExecutionOrchestrator;
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

  static int _safeReadOnlyBatchParallelism(int poolSize) {
    return OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(poolSize);
  }

  ConnectionCircuitBreaker _getCircuitBreaker(String connectionString) {
    return _circuitBreakers.getOrCreate(connectionString);
  }

  /// Resets the circuit breaker for a specific connection string.
  ///
  /// Useful after configuration changes or manual recovery.
  @override
  void resetCircuitBreaker(String connectionString) {
    _circuitBreakers.reset(connectionString);
  }

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

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    final initResult = await _ensureInitialized();

    return initResult.fold((_) async {
      if (connectionString.trim().isEmpty) {
        return Failure(
          domain.ValidationFailure('Connection string cannot be empty'),
        );
      }

      final breaker = _getCircuitBreaker(connectionString);
      return breaker.execute(
        connectionString,
        () async {
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
        },
      );
    }, Failure.new);
  }

  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
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

            final breaker = _getCircuitBreaker(connectionString);
            return breaker.execute(
              connectionString,
              () => _retryCoordinator.executeQueryWithRetry(
                (remainingTimeout) => _queryExecutionOrchestrator.execute(
                  request,
                  connectionString,
                  localConfig,
                  timeout: remainingTimeout,
                  cancellationToken: cancellationToken,
                ),
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

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
    CancellationToken? cancellationToken,
  }) {
    return _batchExecutionOrchestrator.execute(
      agentId: agentId,
      commands: commands,
      database: database,
      options: options,
      timeout: timeout,
      sourceRpcRequestId: sourceRpcRequestId,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
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

            return _retryCoordinator.executeQueryWithRetry(
              (remainingTimeout) => _nonQueryExecutionOrchestrator.execute(
                query,
                parameters,
                connectionString,
                timeout: remainingTimeout,
                cancellationToken: cancellationToken,
                sourceRpcRequestId: sourceRpcRequestId,
              ),
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
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
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
              cancellationToken: cancellationToken,
              sourceRpcRequestId: sourceRpcRequestId,
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
