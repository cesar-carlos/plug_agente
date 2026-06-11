import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:plug_agente/core/constants/rpc_sql_diagnostics_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

typedef ReadOnlyBatchInfrastructureFailureRecorder =
    void Function({
      required String originalSql,
      required String errorMessage,
      String? rpcRequestId,
    });

/// Executes homogeneous read-only SQL batches with a worker pool that reuses a
/// fixed set of pooled ODBC connections instead of acquiring per command.
final class OdbcReadOnlyBatchParallelExecutor {
  OdbcReadOnlyBatchParallelExecutor({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcQueryRunner queryRunner,
    required OdbcConnectionOptionsResolver optionsResolver,
    required MetricsCollector metrics,
    required PoolSemaphore parallelSemaphore,
    required Uuid uuid,
    required ReadOnlyBatchInfrastructureFailureRecorder recordInfrastructureFailure,
  }) : _connectionManager = connectionManager,
       _queryRunner = queryRunner,
       _optionsResolver = optionsResolver,
       _metrics = metrics,
       _parallelSemaphore = parallelSemaphore,
       _uuid = uuid,
       _recordInfrastructureFailure = recordInfrastructureFailure;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcQueryRunner _queryRunner;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final MetricsCollector _metrics;
  final PoolSemaphore _parallelSemaphore;
  final Uuid _uuid;
  final ReadOnlyBatchInfrastructureFailureRecorder _recordInfrastructureFailure;

  static int safeParallelismForPoolSize(int poolSize) {
    return math.max(1, poolSize ~/ 2);
  }

  Future<Result<List<SqlCommandResult>>> execute({
    required String agentId,
    required List<SqlCommand> commands,
    required String connectionString,
    required DatabaseConfig databaseConfig,
    required SqlExecutionOptions options,
    required Duration? timeout,
    required String batchSqlPreview,
    required int poolSize,
    bool allowNativeCompatibleAcquire = false,
    String? sourceRpcRequestId,
  }) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    final safePoolParallelism = safeParallelismForPoolSize(poolSize);
    _parallelSemaphore.resize(safePoolParallelism);
    final parallelism = options.maxParallelReadOnlyBatchItems.clamp(1, safePoolParallelism);
    final acquireOptions = _optionsResolver.forTimeout(
      OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
    );

    _metrics.recordReadOnlyBatchParallel(
      requestedParallelism: options.maxParallelReadOnlyBatchItems,
      effectiveParallelism: parallelism,
    );
    developer.log(
      'Executing read-only batch with pooled worker parallelism',
      name: 'database_gateway',
      level: 800,
      error: {
        'commands': commands.length,
        'parallelism': parallelism,
      },
    );

    final workerConnections = <String>[];
    for (var workerIndex = 0; workerIndex < parallelism; workerIndex++) {
      final remainingTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline);
      if (remainingTimeout != null && remainingTimeout <= Duration.zero) {
        await _releaseWorkerConnections(workerConnections);
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Batch SQL execution timeout before worker pool warm-up',
            context: {
              'timeout': true,
              'timeout_stage': 'sql',
              'stage': 'batch',
              'reason': RpcSqlDiagnosticsConstants.readOnlyParallelGlobalWaitTimeoutReason,
            },
          ),
        );
      }

      final poolResult = allowNativeCompatibleAcquire
          ? await _connectionManager.acquireNativeCompatiblePooledConnection(
              connectionString,
              leaseFallbackOptions: acquireOptions,
              deadline: deadline,
              context: {
                'operation': 'read_only_batch_parallel_worker',
                'worker_index': workerIndex,
              },
            )
          : await _connectionManager.acquirePooledConnection(
              connectionString,
              options: acquireOptions,
              deadline: deadline,
              context: {
                'operation': 'read_only_batch_parallel_worker',
                'worker_index': workerIndex,
              },
            );
      if (poolResult.isError()) {
        await _releaseWorkerConnections(workerConnections);
        final error = poolResult.exceptionOrNull()!;
        _recordInfrastructureFailure(
          originalSql: batchSqlPreview,
          errorMessage: error is domain.Failure ? error.message : error.toString(),
          rpcRequestId: sourceRpcRequestId,
        );
        return Failure(
          error is domain.Failure
              ? error
              : domain.ConnectionFailure('Failed to acquire pooled worker connection for read-only batch'),
        );
      }
      workerConnections.add(poolResult.getOrThrow());
    }

    final results = List<SqlCommandResult?>.filled(commands.length, null);
    var cursor = 0;

    try {
      Future<void> worker(int workerIndex) async {
        final connectionId = workerConnections[workerIndex];
        while (true) {
          final index = cursor++;
          if (index >= commands.length) {
            return;
          }

          final command = commands[index];
          final remainingTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline);
          if (remainingTimeout != null && remainingTimeout <= Duration.zero) {
            results[index] = SqlCommandResult.failure(
              index: index,
              error: 'Batch SQL execution timeout',
            );
            continue;
          }

          final waitStopwatch = Stopwatch()..start();
          try {
            await _parallelSemaphore.acquire(timeout: remainingTimeout ?? timeout);
          } on TimeoutException {
            waitStopwatch.stop();
            _metrics.recordReadOnlyBatchParallelWaitTime(waitStopwatch.elapsed);
            _metrics.recordDiagnosticReason(
              category: 'batch',
              reason: RpcSqlDiagnosticsConstants.readOnlyParallelGlobalWaitTimeoutReason,
            );
            results[index] = SqlCommandResult.failure(
              index: index,
              error: 'Batch SQL execution timeout while waiting for read-only parallel capacity',
            );
            continue;
          }
          waitStopwatch.stop();
          _metrics.recordReadOnlyBatchParallelWaitTime(waitStopwatch.elapsed);

          try {
            final executionTimeout = OdbcExecutionDeadline.remainingFromDeadline(deadline);
            if (executionTimeout != null && executionTimeout <= Duration.zero) {
              results[index] = SqlCommandResult.failure(
                index: index,
                error: 'Batch SQL execution timeout before read-only item execution',
              );
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
            final preparedExecution = OdbcGatewayQueryPreparation.prepareQueryExecution(
              commandRequest,
              databaseConfig,
            );
            final outcome = await _queryRunner.runWithTimeout(
              connId: connectionId,
              request: commandRequest,
              preparedExecution: preparedExecution,
              connectionString: connectionString,
              timeout: executionTimeout ?? timeout,
              executionMode: allowNativeCompatibleAcquire
                  ? 'read_only_batch_parallel_native'
                  : 'read_only_batch_parallel',
            );

            if (!outcome.isSuccess) {
              final error = outcome.error!;
              if (allowNativeCompatibleAcquire && _isInvalidConnectionIdError(error)) {
                _connectionManager.recordPooledExecutionFailure(
                  connectionString: connectionString,
                  connectionId: connectionId,
                  error: error,
                  stage: 'read_only_batch_parallel',
                );
                _connectionManager.markConnectionForDiscard(connectionId);
              }
              final message = error is domain.Failure ? error.message : error.toString();
              _recordInfrastructureFailure(
                originalSql: command.sql.isEmpty ? batchSqlPreview : command.sql,
                errorMessage: message,
                rpcRequestId: sourceRpcRequestId,
              );
              results[index] = SqlCommandResult.failure(index: index, error: message);
              continue;
            }

            final response = outcome.response!;
            final limitedRows = truncateSqlResultRows(response.data, options.maxRows);
            results[index] = SqlCommandResult.success(
              index: index,
              rows: limitedRows,
              rowCount: limitedRows.length,
              affectedRows: response.affectedRows,
              columnMetadata: response.columnMetadata,
            );
          } on TimeoutException {
            results[index] = SqlCommandResult.failure(
              index: index,
              error: 'Batch SQL execution timeout',
            );
          } finally {
            _parallelSemaphore.release();
          }
        }
      }

      await Future.wait(List.generate(parallelism, worker));
    } finally {
      await _releaseWorkerConnections(workerConnections);
    }

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

  Future<void> _releaseWorkerConnections(List<String> connectionIds) async {
    for (final connectionId in connectionIds) {
      await _connectionManager.releaseConnectionSafely(connectionId);
    }
  }

  bool _isInvalidConnectionIdError(Object error) {
    return OdbcErrorInspector.isInvalidConnectionId(error);
  }
}
