import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_investigation_recorder.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_policies.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Executes ODBC queries on a dedicated direct connection (outside the pool).
final class DirectOdbcQueryExecutor {
  DirectOdbcQueryExecutor({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcQueryRunner queryRunner,
    required OdbcConnectionOptionsResolver optionsResolver,
    required MetricsCollector metrics,
    required OdbcQueryExecutionInvestigationRecorder investigationRecorder,
  }) : _connectionManager = connectionManager,
       _queryRunner = queryRunner,
       _optionsResolver = optionsResolver,
       _metrics = metrics,
       _investigationRecorder = investigationRecorder;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcQueryRunner _queryRunner;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final MetricsCollector _metrics;
  final OdbcQueryExecutionInvestigationRecorder _investigationRecorder;

  Future<Result<QueryResponse>> execute(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    ConnectionAcquireOptions? options,
    Duration? timeout,
    bool afterVacuousPooledMulti = false,
    bool allowAdaptiveRetry = true,
    DateTime? deadline,
    CancellationToken? cancellationToken,
  }) async {
    final cancelled = OdbcQueryExecutionPolicies.cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelled != null) {
      stopwatch.stop();
      return Failure(cancelled);
    }

    final effectiveDeadline = deadline ?? OdbcExecutionDeadline.deadlineFor(timeout);
    final leaseResult = await _connectionManager.acquireDirectLease(
      operation: 'query_direct',
      deadline: effectiveDeadline,
    );
    if (leaseResult.isError()) {
      stopwatch.stop();
      final leaseFailure = leaseResult.exceptionOrNull()!;
      _investigationRecorder.recordExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: leaseFailure.toString(),
        executedInDb: false,
      );
      return Failure(leaseFailure);
    }
    final directLease = leaseResult.getOrThrow();
    final cancelledAfterLease = OdbcQueryExecutionPolicies.cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelledAfterLease != null) {
      stopwatch.stop();
      directLease.release();
      return Failure(cancelledAfterLease);
    }
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
          OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
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
              timeout: OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
              executionMode: 'direct',
              cancellationToken: cancellationToken,
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
                  return execute(
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
                    cancellationToken: cancellationToken,
                  );
                }
              }
              stopwatch.stop();
              _metrics.recordFailure(
                queryId: request.id,
                query: request.query,
                executionDuration: stopwatch.elapsed,
                errorMessage: OdbcQueryExecutionPolicies.odbcErrorMessage(error),
              );
              _investigationRecorder.recordExecutionFailure(
                request: request,
                preparedExecution: preparedExecution,
                errorMessage: OdbcQueryExecutionPolicies.odbcErrorMessage(error),
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
            if (afterVacuousPooledMulti &&
                OdbcQueryExecutionPolicies.isVacuousMultiResultResponse(request, response)) {
              _metrics.recordMultiResultDirectStillVacuous();
              developer.log(
                'Direct connection multi-result still vacuous after pooled empty '
                'payload (query_id=${request.id}, '
                'sql_preview=${OdbcQueryExecutionPolicies.previewSqlForLog(preparedExecution.sql)})',
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
          } on CancellationException catch (error) {
            stopwatch.stop();
            _metrics.recordFailure(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              errorMessage: 'SQL execution cancelled',
            );
            _investigationRecorder.recordExecutionFailure(
              request: request,
              preparedExecution: preparedExecution,
              errorMessage: 'SQL execution cancelled',
              executedInDb: false,
            );
            return Failure(
              OdbcQueryExecutionPolicies.mapCancellationFailure(
                error: error,
                operation: 'execute_query_direct',
                request: request,
              ),
            );
          } on TimeoutException catch (error) {
            stopwatch.stop();
            _metrics.recordFailure(
              queryId: request.id,
              query: request.query,
              executionDuration: stopwatch.elapsed,
              errorMessage: 'Query execution timeout',
            );
            _investigationRecorder.recordExecutionFailure(
              request: request,
              preparedExecution: preparedExecution,
              errorMessage: 'Query execution timeout',
              executedInDb: true,
            );
            return Failure(
              OdbcQueryExecutionPolicies.mapTimeoutFailure(
                error: error,
                timeout: timeout,
              ),
            );
          } finally {
            await cleanupOwnedConnection();
          }
        },
        (error) {
          if (OdbcQueryExecutionPolicies.looksLikeTimeoutError(error)) {
            _metrics.recordConnectTimeout();
          }
          stopwatch.stop();
          _metrics.recordFailure(
            queryId: request.id,
            query: request.query,
            executionDuration: stopwatch.elapsed,
            errorMessage: OdbcQueryExecutionPolicies.odbcErrorMessage(error),
          );
          _investigationRecorder.recordExecutionFailure(
            request: request,
            preparedExecution: preparedExecution,
            errorMessage: OdbcQueryExecutionPolicies.odbcErrorMessage(error),
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
}
