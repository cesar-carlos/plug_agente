import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/homogeneous_insert_batch_planner.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/external_services/query_execution_outcome.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

typedef BatchEnsureInitialized = Future<Result<void>> Function();
typedef BatchResolveActiveConfig = Future<Result<Config>> Function();
typedef BatchBuildDatabaseConfig = DatabaseConfig Function(Config config);
typedef BatchResolveConnectionString = String Function(
  Config config,
  DatabaseConfig databaseConfig, {
  String? databaseOverride,
});
typedef BatchInfrastructureFailureRecorder = void Function({
  required String originalSql,
  required String errorMessage,
  String? rpcRequestId,
  String method,
});
typedef BatchSqlExecutionFailureRecorder = void Function({
  required QueryRequest request,
  required OdbcPreparedQueryExecution preparedExecution,
  required String errorMessage,
  required bool executedInDb,
  String method,
});

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
  final bool ownedConnection;
  final bool nativeCompatibleAcquire;
}

class _BatchConnectionState {
  _BatchConnectionState(this.connectionId);

  String? connectionId;
}

/// Routes and executes ODBC SQL batches (transactional, bulk-insert, parallel).
final class OdbcBatchExecutionOrchestrator {
  OdbcBatchExecutionOrchestrator({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcBatchTransactionManager txManager,
    required OdbcBulkInsertExecutor bulkInsertExecutor,
    required OdbcQueryRunner queryRunner,
    required OdbcStatementExecutor statementExecutor,
    required OdbcConnectionOptionsResolver optionsResolver,
    required NativeCompatibleAcquirePolicy nativeCompatiblePolicy,
    required MetricsCollector metrics,
    required OdbcReadOnlyBatchParallelExecutor readOnlyBatchParallelExecutor,
    required PoolSemaphore readOnlyBatchParallelSemaphore,
    required Uuid uuid,
    required int poolSize,
    required BatchEnsureInitialized ensureInitialized,
    required BatchResolveActiveConfig resolveActiveConfig,
    required BatchBuildDatabaseConfig buildDatabaseConfig,
    required BatchResolveConnectionString resolveConnectionString,
    required BatchInfrastructureFailureRecorder recordInfrastructureFailure,
    required BatchSqlExecutionFailureRecorder recordExecutionFailure,
  }) : _connectionManager = connectionManager,
       _txManager = txManager,
       _bulkInsertExecutor = bulkInsertExecutor,
       _queryRunner = queryRunner,
       _statementExecutor = statementExecutor,
       _optionsResolver = optionsResolver,
       _nativeCompatiblePolicy = nativeCompatiblePolicy,
       _metrics = metrics,
       _readOnlyBatchParallelExecutor = readOnlyBatchParallelExecutor,
       _readOnlyBatchParallelSemaphore = readOnlyBatchParallelSemaphore,
       _uuid = uuid,
       _poolSize = poolSize,
       _ensureInitialized = ensureInitialized,
       _resolveActiveConfig = resolveActiveConfig,
       _buildDatabaseConfig = buildDatabaseConfig,
       _resolveConnectionString = resolveConnectionString,
       _recordInfrastructureFailure = recordInfrastructureFailure,
       _recordExecutionFailure = recordExecutionFailure;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcBatchTransactionManager _txManager;
  final OdbcBulkInsertExecutor _bulkInsertExecutor;
  final OdbcQueryRunner _queryRunner;
  final OdbcStatementExecutor _statementExecutor;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final MetricsCollector _metrics;
  final OdbcReadOnlyBatchParallelExecutor _readOnlyBatchParallelExecutor;
  final PoolSemaphore _readOnlyBatchParallelSemaphore;
  final Uuid _uuid;
  final int _poolSize;
  final BatchEnsureInitialized _ensureInitialized;
  final BatchResolveActiveConfig _resolveActiveConfig;
  final BatchBuildDatabaseConfig _buildDatabaseConfig;
  final BatchResolveConnectionString _resolveConnectionString;
  final BatchInfrastructureFailureRecorder _recordInfrastructureFailure;
  final BatchSqlExecutionFailureRecorder _recordExecutionFailure;

  static const int _batchSqlInvestigationPreviewMaxChars = 2000;

  Future<Result<List<SqlCommandResult>>> execute({
    required String agentId,
    required List<SqlCommand> commands,
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
        OdbcGatewayBufferExpansion.messageIndicatesBufferTooSmall(OdbcErrorInspector.message(failure));
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
        if (!_shouldFallbackReadOnlyBatchNativePool(error, attempt)) {
          return result;
        }
        _recordReadOnlyBatchNativePoolFallback(
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

  bool _shouldFallbackReadOnlyBatchNativePool(Object error, int attempt) {
    if (attempt > 0) {
      return false;
    }
    final failure = error is domain.Failure ? error : OdbcFailureMapper.mapQueryError(error);
    return failure is domain.ConnectionFailure ||
        _queryFailureIndicatesInvalidConnectionId(failure) ||
        failure.context['connectionFailed'] == true ||
        failure.context['timeout'] == true;
  }

  void _recordReadOnlyBatchNativePoolFallback({
    required String connectionString,
    required Object error,
    required String stage,
  }) {
    _metrics.recordReadOnlyBatchNativePoolFallback();
    _metrics.recordDiagnosticReason(
      category: 'batch',
      reason: RpcSqlDiagnosticsConstants.readOnlyBatchNativePoolFallbackReason,
    );
    _connectionManager.recordPooledExecutionFailure(
      connectionString: connectionString,
      error: error,
      stage: 'read_only_batch_native_pool_$stage',
    );
    developer.log(
      'Read-only parallel batch falling back from native pool to lease pool',
      name: 'database_gateway',
      level: 900,
      error: {
        'stage': stage,
        'error': OdbcErrorInspector.message(error),
      },
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
        _recordInfrastructureFailure(
          originalSql: batchSqlPreview,
          errorMessage: OdbcErrorInspector.message(err),
          rpcRequestId: sourceRpcRequestId,
        );
        return Failure(err);
      }
      final directLease = leaseResult.getOrThrow();
      final remainingTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
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
          _recordInfrastructureFailure(
            originalSql: batchSqlPreview,
            errorMessage: OdbcErrorInspector.message(error),
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

    final remainingTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout;
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
      _recordInfrastructureFailure(
        originalSql: batchSqlPreview,
        errorMessage: OdbcErrorInspector.message(error),
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
              _recordExecutionFailure(
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

            _recordExecutionFailure(
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
        OdbcExecutionDeadline.remainingFromDeadline(context.deadline),
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

  Duration? _remainingTimeout(DateTime? deadline) {
    final remaining = OdbcExecutionDeadline.remainingFromDeadline(deadline);
    if (remaining != null && remaining <= Duration.zero) {
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

  bool _queryFailureIndicatesInvalidConnectionId(domain.Failure failure) {
    return OdbcErrorInspector.isInvalidConnectionId(failure);
  }
}
