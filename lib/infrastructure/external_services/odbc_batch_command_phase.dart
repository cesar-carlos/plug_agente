import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/batch_transaction.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_execution_types.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_batch_transaction_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/external_services/query_execution_outcome.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

final class OdbcBatchCommandPhase {
  OdbcBatchCommandPhase({
    required OdbcBatchTransactionManager txManager,
    required OdbcQueryRunner queryRunner,
    required OdbcStatementExecutor statementExecutor,
    required OdbcConnectionOptionsResolver optionsResolver,
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcBatchFailureMapper failureMapper,
    required Uuid uuid,
    required BatchSqlExecutionFailureRecorder recordExecutionFailure,
  }) : _txManager = txManager,
       _queryRunner = queryRunner,
       _statementExecutor = statementExecutor,
       _optionsResolver = optionsResolver,
       _connectionManager = connectionManager,
       _failureMapper = failureMapper,
       _uuid = uuid,
       _recordExecutionFailure = recordExecutionFailure;

  final OdbcBatchTransactionManager _txManager;
  final OdbcQueryRunner _queryRunner;
  final OdbcStatementExecutor _statementExecutor;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcBatchFailureMapper _failureMapper;
  final Uuid _uuid;
  final BatchSqlExecutionFailureRecorder _recordExecutionFailure;

  Future<Result<List<SqlCommandResult>>> executeBatchCommands({
    required BatchExecutionContext context,
    required BatchConnectionState connectionState,
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

            if (_failureMapper.shouldRecoverNonTransactionalBatchConnection(failure)) {
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

  Future<QueryExecutionOutcome> _retryBatchCommandAfterConnectionFailure({
    required BatchExecutionContext context,
    required BatchConnectionState connectionState,
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

    if (_failureMapper.queryFailureIndicatesInvalidConnectionId(failure)) {
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
}
