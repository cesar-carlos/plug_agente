import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/homogeneous_insert_batch_planner.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_command_phase.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_connection_phase.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_types.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_routing_phases.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_support.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_bulk_insert_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_read_only_batch_parallel_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

export 'odbc_batch_execution_types.dart';

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
       _metrics = metrics,
       _failureMapper = OdbcBatchFailureMapper(
         connectionManager: connectionManager,
         metrics: metrics,
       ),
       _transactionSupport = OdbcBatchTransactionSupport(metrics: metrics),
       _connectionPhase = OdbcBatchConnectionPhase(
         connectionManager: connectionManager,
         optionsResolver: optionsResolver,
         nativeCompatiblePolicy: nativeCompatiblePolicy,
         ensureInitialized: ensureInitialized,
         resolveActiveConfig: resolveActiveConfig,
         buildDatabaseConfig: buildDatabaseConfig,
         resolveConnectionString: resolveConnectionString,
         recordInfrastructureFailure: recordInfrastructureFailure,
       ),
       _commandPhase = OdbcBatchCommandPhase(
         txManager: txManager,
         queryRunner: queryRunner,
         statementExecutor: statementExecutor,
         optionsResolver: optionsResolver,
         connectionManager: connectionManager,
         failureMapper: OdbcBatchFailureMapper(
           connectionManager: connectionManager,
           metrics: metrics,
         ),
         uuid: uuid,
         recordExecutionFailure: recordExecutionFailure,
       ),
       _routingPhases = OdbcBatchRoutingPhases(
         connectionManager: connectionManager,
         txManager: txManager,
         bulkInsertExecutor: bulkInsertExecutor,
         readOnlyBatchParallelExecutor: readOnlyBatchParallelExecutor,
         readOnlyBatchParallelSemaphore: readOnlyBatchParallelSemaphore,
         nativeCompatiblePolicy: nativeCompatiblePolicy,
         connectionPhase: OdbcBatchConnectionPhase(
           connectionManager: connectionManager,
           optionsResolver: optionsResolver,
           nativeCompatiblePolicy: nativeCompatiblePolicy,
           ensureInitialized: ensureInitialized,
           resolveActiveConfig: resolveActiveConfig,
           buildDatabaseConfig: buildDatabaseConfig,
           resolveConnectionString: resolveConnectionString,
           recordInfrastructureFailure: recordInfrastructureFailure,
         ),
         failureMapper: OdbcBatchFailureMapper(
           connectionManager: connectionManager,
           metrics: metrics,
         ),
         transactionSupport: OdbcBatchTransactionSupport(metrics: metrics),
         metrics: metrics,
         ensureInitialized: ensureInitialized,
         resolveActiveConfig: resolveActiveConfig,
         buildDatabaseConfig: buildDatabaseConfig,
         resolveConnectionString: resolveConnectionString,
         poolSize: poolSize,
       );

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcBatchTransactionManager _txManager;
  final MetricsCollector _metrics;
  final OdbcBatchFailureMapper _failureMapper;
  final OdbcBatchTransactionSupport _transactionSupport;
  final OdbcBatchConnectionPhase _connectionPhase;
  final OdbcBatchCommandPhase _commandPhase;
  final OdbcBatchRoutingPhases _routingPhases;

  static const int _batchSqlInvestigationPreviewMaxChars = 2000;

  Future<Result<List<SqlCommandResult>>> execute({
    required String agentId,
    required List<SqlCommand> commands,
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
    CancellationToken? cancellationToken,
  }) async {
    final effectiveTimeout =
        timeout ??
        _transactionSupport.timeoutFromSqlExecutionOptions(options) ??
        (options.transaction ? ConnectionConstants.defaultTransactionalBatchTimeout : null);
    final batchPreview = _previewBatchCommandsForInvestigation(commands);
    final bulkInsertPlan = await _routingPhases.tryHomogeneousInsertBatchAutoRoutePlan(commands);
    if (bulkInsertPlan != null) {
      return _routingPhases.executeHomogeneousInsertBatchAsBulk(
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
      _routingPhases.recordBulkInsertRecommendation(commands);
    }
    if (_routingPhases.shouldUseParallelReadOnlyBatch(commands, options)) {
      return _routingPhases.executeParallelReadOnlyBatch(
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
      final contextResult = await _connectionPhase.prepareBatchExecutionContext(
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
      final connectionState = BatchConnectionState(context.connectionId);
      var recycleAfterRelease = false;
      BatchTransactionGuard? transaction;
      try {
        final batchAccessMode = _transactionSupport.inferBatchAccessMode(commands);
        final beginResult = await _txManager.beginIfNeeded(
          connectionId: connectionState.connectionId!,
          transactionEnabled: options.transaction,
          lockTimeout: _transactionSupport.transactionLockTimeout(
            options: options,
            timeout: effectiveTimeout,
          ),
          accessMode: batchAccessMode,
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
          } else if (options.transaction &&
              attempt == 0 &&
              _failureMapper.queryFailureIndicatesInvalidConnectionId(beginFailure)) {
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

          final commandResult = await _commandPhase.executeBatchCommands(
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
            if (_failureMapper.shouldFallbackTransactionalNativePoolToDirect(
              context: context,
              error: commandFailure,
              attempt: attempt,
            )) {
              _failureMapper.recordTransactionalNativePoolFallback(
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
            _transactionSupport.maybeRecordTransactionalBatchDeadlineNearStall(
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
}
