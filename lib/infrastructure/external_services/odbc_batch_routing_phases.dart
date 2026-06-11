import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/homogeneous_insert_batch_planner.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_connection_phase.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_types.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_support.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

final class OdbcBatchRoutingPhases {
  OdbcBatchRoutingPhases({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcBatchTransactionManager txManager,
    required OdbcBulkInsertExecutor bulkInsertExecutor,
    required OdbcReadOnlyBatchParallelExecutor readOnlyBatchParallelExecutor,
    required PoolSemaphore readOnlyBatchParallelSemaphore,
    required NativeCompatibleAcquirePolicy nativeCompatiblePolicy,
    required OdbcBatchConnectionPhase connectionPhase,
    required OdbcBatchFailureMapper failureMapper,
    required OdbcBatchTransactionSupport transactionSupport,
    required MetricsCollector metrics,
    required BatchEnsureInitialized ensureInitialized,
    required BatchResolveActiveConfig resolveActiveConfig,
    required BatchBuildDatabaseConfig buildDatabaseConfig,
    required BatchResolveConnectionString resolveConnectionString,
    required int poolSize,
  }) : _connectionManager = connectionManager,
       _txManager = txManager,
       _bulkInsertExecutor = bulkInsertExecutor,
       _readOnlyBatchParallelExecutor = readOnlyBatchParallelExecutor,
       _readOnlyBatchParallelSemaphore = readOnlyBatchParallelSemaphore,
       _nativeCompatiblePolicy = nativeCompatiblePolicy,
       _connectionPhase = connectionPhase,
       _failureMapper = failureMapper,
       _transactionSupport = transactionSupport,
       _metrics = metrics,
       _ensureInitialized = ensureInitialized,
       _resolveActiveConfig = resolveActiveConfig,
       _buildDatabaseConfig = buildDatabaseConfig,
       _resolveConnectionString = resolveConnectionString,
       _poolSize = poolSize;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcBatchTransactionManager _txManager;
  final OdbcBulkInsertExecutor _bulkInsertExecutor;
  final OdbcReadOnlyBatchParallelExecutor _readOnlyBatchParallelExecutor;
  final PoolSemaphore _readOnlyBatchParallelSemaphore;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final OdbcBatchConnectionPhase _connectionPhase;
  final OdbcBatchFailureMapper _failureMapper;
  final OdbcBatchTransactionSupport _transactionSupport;
  final MetricsCollector _metrics;
  final BatchEnsureInitialized _ensureInitialized;
  final BatchResolveActiveConfig _resolveActiveConfig;
  final BatchBuildDatabaseConfig _buildDatabaseConfig;
  final BatchResolveConnectionString _resolveConnectionString;
  final int _poolSize;

  bool shouldUseParallelReadOnlyBatch(
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

  Future<HomogeneousInsertBatchPlan?> tryHomogeneousInsertBatchAutoRoutePlan(
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

  void recordBulkInsertRecommendation(List<SqlCommand> commands) {
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

  Future<Result<List<SqlCommandResult>>> executeHomogeneousInsertBatchAsBulk({
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
      final bulkResult = await _executeBulkInsertDirect(
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
      final contextResult = await _connectionPhase.prepareBatchExecutionContext(
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
      final connectionState = BatchConnectionState(context.connectionId);
      var recycleAfterRelease = false;
      BatchTransactionGuard? transaction;
      try {
        final beginResult = await _txManager.beginIfNeeded(
          connectionId: connectionState.connectionId!,
          transactionEnabled: true,
          lockTimeout: _transactionSupport.transactionLockTimeout(
            options: options,
            timeout: timeout,
          ),
          accessMode: TransactionAccessMode.readWrite,
        );
        if (beginResult.isError()) {
          final beginFailure = beginResult.exceptionOrNull()! as domain.Failure;
          if (_failureMapper.shouldFallbackTransactionalNativePoolToDirect(
            context: context,
            error: beginFailure,
            attempt: attempt,
          )) {
            _failureMapper.recordTransactionalNativePoolFallback(
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
            if (_failureMapper.shouldFallbackTransactionalNativePoolToDirect(
              context: context,
              error: bulkFailure,
              attempt: attempt,
            )) {
              _failureMapper.recordTransactionalNativePoolFallback(
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
        if (_failureMapper.shouldFallbackTransactionalNativePoolToDirect(
          context: context,
          error: error,
          attempt: attempt,
        )) {
          _failureMapper.recordTransactionalNativePoolFallback(
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
          await _connectionPhase.releaseBatchConnection(
            BatchExecutionContext(
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

  Future<Result<List<SqlCommandResult>>> executeParallelReadOnlyBatch({
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
    final safePoolParallelism = OdbcReadOnlyBatchParallelExecutor.safeParallelismForPoolSize(_poolSize);
    _readOnlyBatchParallelSemaphore.resize(safePoolParallelism);

    final useNativeCompatiblePool = _nativeCompatiblePolicy.shouldUseReadOnlyBatchParallel(
      databaseType: localConfig.databaseType,
      commands: commands,
      timeout: timeout,
      connectionString: connectionString,
    );

    var allowNativeCompatibleAcquire = useNativeCompatiblePool;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (allowNativeCompatibleAcquire) {
        _metrics.recordReadOnlyBatchNativePoolPath();
        developer.log(
          'Executing read-only batch with native-compatible ODBC pool parallelism',
          name: 'database_gateway',
          level: 800,
          error: {
            'commands': commands.length,
            'parallelism': options.maxParallelReadOnlyBatchItems.clamp(1, safePoolParallelism),
          },
        );
      }

      final result = await _readOnlyBatchParallelExecutor.execute(
        agentId: agentId,
        commands: commands,
        connectionString: connectionString,
        databaseConfig: localConfig,
        options: options,
        timeout: timeout,
        batchSqlPreview: batchSqlPreview,
        poolSize: _poolSize,
        allowNativeCompatibleAcquire: allowNativeCompatibleAcquire,
        sourceRpcRequestId: sourceRpcRequestId,
      );

      if (!allowNativeCompatibleAcquire || attempt > 0) {
        return result;
      }

      if (result.isError()) {
        final error = result.exceptionOrNull()!;
        if (!_failureMapper.shouldFallbackReadOnlyBatchNativePool(
          error: error,
          attempt: attempt,
        )) {
          return result;
        }
        _failureMapper.recordReadOnlyBatchNativePoolFallback(
          connectionString: connectionString,
          error: error,
          stage: 'worker_warmup',
        );
        allowNativeCompatibleAcquire = false;
        continue;
      }

      return result;
    }

    return Failure(
      domain.ConnectionFailure.withContext(
        message: 'Read-only parallel batch failed after native pool fallback',
        context: {
          'operation': 'read_only_batch_parallel',
          'reason': RpcSqlDiagnosticsConstants.readOnlyBatchNativePoolFallbackReason,
        },
      ),
    );
  }

  Future<Result<int>> _executeBulkInsertDirect(
    BulkInsertRequest request, {
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
}
