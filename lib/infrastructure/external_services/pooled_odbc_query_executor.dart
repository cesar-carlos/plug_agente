import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/direct_odbc_query_executor.dart';
import 'package:plug_agente/infrastructure/external_services/native_compatible_acquire_policy.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_investigation_recorder.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_execution_policies.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Executes ODBC queries using pooled connections with adaptive retry and fallbacks.
final class PooledOdbcQueryExecutor {
  PooledOdbcQueryExecutor({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcQueryRunner queryRunner,
    required OdbcConnectionOptionsResolver optionsResolver,
    required NativeCompatibleAcquirePolicy nativeCompatiblePolicy,
    required MetricsCollector metrics,
    required DirectOdbcQueryExecutor directExecutor,
    required OdbcQueryExecutionInvestigationRecorder investigationRecorder,
  }) : _connectionManager = connectionManager,
       _queryRunner = queryRunner,
       _optionsResolver = optionsResolver,
       _nativeCompatiblePolicy = nativeCompatiblePolicy,
       _metrics = metrics,
       _directExecutor = directExecutor,
       _investigationRecorder = investigationRecorder;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcQueryRunner _queryRunner;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final NativeCompatibleAcquirePolicy _nativeCompatiblePolicy;
  final MetricsCollector _metrics;
  final DirectOdbcQueryExecutor _directExecutor;
  final OdbcQueryExecutionInvestigationRecorder _investigationRecorder;

  Future<Result<QueryResponse>> execute(
    QueryRequest request,
    String connectionString,
    Stopwatch stopwatch, {
    required OdbcPreparedQueryExecution preparedExecution,
    required Duration? timeout,
    ConnectionAcquireOptions? acquireOptions,
    bool allowAdaptiveRetry = true,
    bool allowNativeCompatibleAcquire = false,
    DateTime? deadline,
    CancellationToken? cancellationToken,
    DatabaseType? databaseType,
  }) async {
    final effectiveDeadline = deadline ?? OdbcExecutionDeadline.deadlineFor(timeout);
    final poolAcquireOptions =
        acquireOptions ??
        _optionsResolver.forTimeout(
          OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
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
        errorMessage: OdbcQueryExecutionPolicies.odbcErrorMessage(error),
      );

      _investigationRecorder.recordExecutionFailure(
        request: request,
        preparedExecution: preparedExecution,
        errorMessage: OdbcQueryExecutionPolicies.odbcErrorMessage(error),
        executedInDb: false,
      );

      return Failure(failure);
    }

    final cancelledAfterAcquire = OdbcQueryExecutionPolicies.cooperativeCancelFailure(
      request: request,
      cancellationToken: cancellationToken,
    );
    if (cancelledAfterAcquire != null) {
      stopwatch.stop();
      await _connectionManager.releaseConnectionSafely(poolResult.getOrThrow());
      return Failure(cancelledAfterAcquire);
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
        timeout: OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
        executionMode: allowNativeCompatibleAcquire ? 'native_compatible' : 'pooled',
        cancellationToken: cancellationToken,
        databaseType: databaseType,
      );

      if (outcome.isSuccess && allowNativeCompatibleAcquire && timeout != null && timeout > Duration.zero) {
        _nativeCompatiblePolicy.rememberNativeCompatibleTimeout(
          connectionString: connectionString,
          timeout: timeout,
        );
      }

      if (!outcome.isSuccess) {
        final error = outcome.error!;
        if (OdbcQueryExecutionPolicies.isInvalidConnectionIdError(error)) {
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
          return _directExecutor.execute(
            request,
            connectionString,
            stopwatch,
            preparedExecution: preparedExecution,
            timeout: timeout,
            cancellationToken: cancellationToken,
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
          return execute(
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
            cancellationToken: cancellationToken,
          );
        }

        stopwatch.stop();

        developer.log(
          'Query ${request.id} failed',
          name: 'database_gateway',
          level: 1000,
          error: error,
        );

        final msg = OdbcQueryExecutionPolicies.odbcErrorMessage(error);
        _metrics.recordFailure(
          queryId: request.id,
          query: request.query,
          executionDuration: stopwatch.elapsed,
          errorMessage: msg,
        );

        _investigationRecorder.recordExecutionFailure(
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
      if (OdbcQueryExecutionPolicies.isVacuousMultiResultResponse(request, response)) {
        _metrics.recordMultiResultPoolVacuousFallback();
        developer.log(
          'Pooled executeQueryMultiFull returned no rows or row-count items; '
          'retrying on a direct connection (pool/driver quirk) '
          '(query_id=${request.id}, '
          'sql_preview=${OdbcQueryExecutionPolicies.previewSqlForLog(preparedExecution.sql)})',
          name: 'database_gateway',
          level: 800,
        );
        _metrics.recordDirectConnectionFallback();
        await _connectionManager.releaseConnectionSafely(connId);
        releasedConnectionEarly = true;
        return _directExecutor.execute(
          request,
          connectionString,
          stopwatch,
          preparedExecution: preparedExecution,
          timeout: timeout,
          afterVacuousPooledMulti: true,
          deadline: effectiveDeadline,
          cancellationToken: cancellationToken,
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
          operation: 'execute_query',
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
      if (!releasedConnectionEarly) {
        await _connectionManager.releaseConnectionSafely(connId);
      }
    }
  }
}
