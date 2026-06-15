import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart' hide DatabaseType;
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_options_resolver.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_connection_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_runner.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/connection_acquire_options_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Pooled and direct ODBC non-query execution after config/retry resolution.
class OdbcNonQueryExecutionOrchestrator {
  OdbcNonQueryExecutionOrchestrator({
    required OdbcGatewayConnectionManager connectionManager,
    required OdbcService service,
    required OdbcStatementExecutor statementExecutor,
    required OdbcConnectionOptionsResolver optionsResolver,
    required MetricsCollector metrics,
    OdbcInFlightExecutionRegistry? inFlightRegistry,
  }) : _connectionManager = connectionManager,
       _service = service,
       _statementExecutor = statementExecutor,
       _optionsResolver = optionsResolver,
       _metrics = metrics,
       _inFlightRegistry = inFlightRegistry;

  final OdbcGatewayConnectionManager _connectionManager;
  final OdbcService _service;
  final OdbcStatementExecutor _statementExecutor;
  final OdbcConnectionOptionsResolver _optionsResolver;
  final MetricsCollector _metrics;
  final OdbcInFlightExecutionRegistry? _inFlightRegistry;

  Future<Result<int>> execute(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) {
    if (cancellationToken?.isCancelled ?? false) {
      return Future<Result<int>>.value(
        Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'Non-query execution cancelled',
            context: const {'cooperative_cancel': true},
          ),
        ),
      );
    }

    return _executeNonQueryInternal(
      query,
      parameters,
      connectionString,
      timeout: timeout,
      cancellationToken: cancellationToken,
      sourceRpcRequestId: sourceRpcRequestId,
    );
  }

  Future<Result<int>> _executeNonQueryInternal(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) async {
    final deadline = OdbcExecutionDeadline.deadlineFor(timeout);
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
    final inFlightRequestId = _inFlightTrackingKey(sourceRpcRequestId);

    try {
      _registerInFlightExecution(inFlightRequestId, connId);
      final result = await _runNonQueryWithTimeout(
        connectionId: connId,
        query: query,
        parameters: parameters,
        timeout: OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
        inFlightRequestId: inFlightRequestId,
        cancellationToken: cancellationToken,
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
            cancellationToken: cancellationToken,
            sourceRpcRequestId: sourceRpcRequestId,
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
      _unregisterInFlightExecution(inFlightRequestId);
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
    String? inFlightRequestId,
    CancellationToken? cancellationToken,
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
          inFlightRegistry: _inFlightRegistry,
          inFlightRequestId: inFlightRequestId,
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
          inFlightRegistry: _inFlightRegistry,
          inFlightRequestId: inFlightRequestId,
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

  Future<Result<int>> _executeNonQueryWithoutPool(
    String query,
    Map<String, dynamic>? parameters,
    String connectionString, {
    Duration? timeout,
    DateTime? deadline,
    CancellationToken? cancellationToken,
    String? sourceRpcRequestId,
  }) async {
    final effectiveDeadline = deadline ?? OdbcExecutionDeadline.deadlineFor(timeout);
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
        options: _optionsResolver
            .forTimeout(
              OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
            )
            .toOdbcConnectionOptions(),
      );
      return await connectResult.fold(
        (connection) async {
          final inFlightRequestId = _inFlightTrackingKey(sourceRpcRequestId);
          try {
            _registerInFlightExecution(inFlightRequestId, connection.id);
            final result = await _runNonQueryWithTimeout(
              connectionId: connection.id,
              query: query,
              parameters: parameters,
              timeout: OdbcExecutionDeadline.remainingFromDeadline(effectiveDeadline) ?? timeout,
              executionMode: 'direct_non_query',
              inFlightRequestId: inFlightRequestId,
              cancellationToken: cancellationToken,
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
            _unregisterInFlightExecution(inFlightRequestId);
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

  bool _isInvalidConnectionIdError(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  bool _looksLikeTimeoutError(Object error) => OdbcErrorInspector.isTimeout(error);

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

  String? _inFlightTrackingKey(String? sourceRpcRequestId) {
    final normalized = sourceRpcRequestId?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  void _registerInFlightExecution(String? requestId, String connectionId) {
    if (requestId == null || requestId.isEmpty) {
      return;
    }
    _inFlightRegistry?.register(
      requestId,
      OdbcInFlightExecutionHandle(connectionId: connectionId),
    );
  }

  void _unregisterInFlightExecution(String? requestId) {
    if (requestId == null || requestId.isEmpty) {
      return;
    }
    _inFlightRegistry?.unregister(requestId);
  }
}
