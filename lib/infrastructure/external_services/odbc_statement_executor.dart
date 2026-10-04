import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_prepared_statement_cache_policy.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

/// Low-level ODBC statement operations used by `OdbcDatabaseGateway`.
///
/// Owns prepared-statement preparation/caching/execution and the native async
/// query lifecycle, including timeout cancellation. It is intentionally
/// orchestration-free: callers own the per-connection prepared-statement cache
/// map and decide which execution path to take. The connection-discard signal
/// is injected so this unit stays decoupled from the connection manager.
final class OdbcStatementExecutor {
  OdbcStatementExecutor({
    required OdbcService service,
    required MetricsCollector metrics,
    required void Function(String connectionId) markConnectionForDiscard,
  }) : _service = service,
       _metrics = metrics,
       _markConnectionForDiscard = markConnectionForDiscard;

  final OdbcService _service;
  final MetricsCollector _metrics;
  final void Function(String connectionId) _markConnectionForDiscard;
  final Set<(String, int)> _pendingStatements = {};
  final Set<(String, int)> _deferredCloses = {};
  int _generation = 0;

  /// Old completions must never close a handle belonging to a recovered worker.
  void invalidateAfterWorkerRecovery() {
    _generation++;
    _pendingStatements.clear();
    _deferredCloses.clear();
  }

  static const int maxPreparedStatementsPerConnection = 64;
  static const int _asyncRequestPendingStatus = 0;
  static const int _asyncRequestReadyStatus = 1;
  static const int _asyncRequestErrorStatus = -1;
  static const int _asyncRequestCancelledStatus = -2;
  static const Duration _asyncRequestPollInterval = Duration(milliseconds: 20);

  /// Returns a prepared statement id for [statementKey], reusing a cached entry
  /// when present (LRU touch) or preparing a new one. Evicts the oldest entry
  /// when the per-connection cache is full.
  Future<Result<int>> getOrPrepareStatement({
    required String connectionId,
    required OdbcPreparedQueryExecution preparedExecution,
    required Map<String, int> preparedStatements,
    required String statementKey,
    Duration? timeout,
    OdbcPreparedStatementCachePolicy cachePolicy = OdbcPreparedStatementCachePolicy.leasePool,
  }) async {
    if (cachePolicy.dartLruEnabled) {
      final existingStmtId = preparedStatements[statementKey];
      if (existingStmtId != null) {
        if (_pendingStatements.contains((connectionId, existingStmtId))) {
          return Failure(
            domain.QueryExecutionFailure.withContext(
              message: 'Prepared statement is still running',
              context: const {'outcome_unknown': true, 'retryable': false},
            ),
          );
        }
        preparedStatements.remove(statementKey);
        preparedStatements[statementKey] = existingStmtId;
        _metrics.recordPreparedStatementReuse();
        return Success(existingStmtId);
      }
    }

    _metrics.recordPreparedStatementCacheMiss();

    final timeoutMs = timeout?.inMilliseconds ?? 0;
    final prepareStopwatch = Stopwatch()..start();
    final prepareResult = preparedExecution.parameters != null && preparedExecution.parameters!.isNotEmpty
        ? await _service.prepareNamed(
            connectionId,
            preparedExecution.sql,
            timeoutMs: timeoutMs,
          )
        : await _service.prepare(
            connectionId,
            preparedExecution.sql,
            timeoutMs: timeoutMs,
          );
    prepareStopwatch.stop();
    _metrics.recordPreparedPrepareTime(prepareStopwatch.elapsed);

    if (prepareResult.isError()) {
      return Failure(prepareResult.exceptionOrNull()!);
    }

    final stmtId = prepareResult.getOrThrow();
    if (cachePolicy.dartLruEnabled) {
      if (preparedStatements.length >= maxPreparedStatementsPerConnection) {
        final oldestKey = preparedStatements.keys.first;
        final oldestStmtId = preparedStatements.remove(oldestKey);
        if (oldestStmtId != null) {
          final closed = await closePreparedStatements(connectionId, <int>[oldestStmtId]);
          if (closed.isError()) {
            preparedStatements[statementKey] = stmtId;
            return Failure(closed.exceptionOrNull()!);
          }
        }
      }
      preparedStatements[statementKey] = stmtId;
    } else {
      preparedStatements['$statementKey::$stmtId'] = stmtId;
    }
    return Success(stmtId);
  }

  Future<Result<QueryResult>> _executePreparedStatement({
    required String connectionId,
    required OdbcPreparedQueryExecution preparedExecution,
    required int stmtId,
    StatementOptions? options,
  }) {
    final parameters = preparedExecution.parameters;
    if (parameters != null && parameters.isNotEmpty) {
      return _service.executePreparedNamed(
        connectionId,
        stmtId,
        parameters,
        options,
      );
    }

    return _service.executePreparedParamValuesFromObjects(
      connectionId,
      stmtId,
      const <Object?>[],
      options,
    );
  }

  /// Executes a prepared statement, applying [timeout] when provided. On
  /// timeout the connection is marked for discard and a best-effort cancel is
  /// issued before a [TimeoutException] propagates.
  Future<Result<QueryResult>> executePreparedStatementWithTimeout({
    required String connectionId,
    required OdbcPreparedQueryExecution preparedExecution,
    required int statementId,
    Duration? timeout,
    OdbcInFlightExecutionRegistry? inFlightRegistry,
    String? inFlightRequestId,
    String? inFlightExecutionId,
  }) async {
    if (inFlightRegistry != null && inFlightRequestId != null && inFlightRequestId.isNotEmpty) {
      inFlightRegistry.bindStatement(
        inFlightRequestId,
        statementId,
        executionId: inFlightExecutionId,
      );
    }

    final statementOptions = StatementOptions(
      timeout: timeout,
      initialBufferSize: ConnectionConstants.defaultInitialResultBufferBytes,
    );
    final execution = _executePreparedStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      stmtId: statementId,
      options: statementOptions,
    );
    final handle = (connectionId, statementId);
    final generation = _generation;
    _pendingStatements.add(handle);
    final trackedExecution = execution.then(
      (result) async {
        if (generation != _generation) {
          return Failure<QueryResult, Exception>(
            domain.QueryExecutionFailure.withContext(
              message: 'Statement completion belongs to an obsolete runtime generation',
              context: const {'reason': 'odbc_generation_changed', 'outcome_unknown': true, 'retryable': false},
            ),
          );
        }
        if (result.isError() && OdbcErrorInspector.outcomeUnknown(result.exceptionOrNull()!)) {
          _markConnectionForDiscard(connectionId);
          return result;
        }
        _pendingStatements.remove(handle);
        if (_deferredCloses.remove(handle)) await closePreparedStatements(connectionId, [statementId]);
        return result;
      },
      onError: (Object error, StackTrace stack) {
        _markConnectionForDiscard(connectionId);
        return Failure<QueryResult, Exception>(OdbcFailureMapper.mapQueryError(error));
      },
    );
    if (timeout == null) {
      return trackedExecution;
    }

    return trackedExecution.timeout(
      timeout,
      onTimeout: () async {
        _markConnectionForDiscard(connectionId);
        unawaited(
          _cancelPreparedStatementForTimeout(
            connectionId: connectionId,
            statementId: statementId,
          ),
        );
        throw QueryError(
          message: 'Prepared statement execution deadline exceeded',
          details: OdbcErrorDetails(
            code: OdbcErrorCode.timeout,
            operation: 'executePrepared',
            connectionId: connectionId,
            outcomeUnknown: true,
          ),
        );
      },
    );
  }

  Future<Result<void>> closePreparedStatements(
    String connectionId,
    Iterable<int> stmtIds,
  ) async {
    final errors = <domain.Failure>[];
    for (final stmtId in stmtIds) {
      final handle = (connectionId, stmtId);
      if (_pendingStatements.contains(handle)) {
        _deferredCloses.add(handle);
        continue;
      }
      try {
        final closed = await _service.closeStatement(connectionId, stmtId);
        if (closed.isError()) {
          errors.add(OdbcFailureMapper.mapQueryError(closed.exceptionOrNull()!, operation: 'closeStatement'));
          _markConnectionForDiscard(connectionId);
        }
      } on Object catch (error) {
        errors.add(OdbcFailureMapper.mapQueryError(error, operation: 'closeStatement'));
        _markConnectionForDiscard(connectionId);
        developer.log(
          'Failed to close prepared statement after execution',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      }
    }
    if (errors.isEmpty) return const Success(unit);
    _metrics.recordPoolReleaseFailure();
    return Failure(
      domain.QueryExecutionFailure.withContext(
        message: 'Prepared statement cleanup failed',
        cause: errors.first,
        context: {
          'operation': 'closeStatement',
          'secondary_errors': [for (final error in errors) error.context],
        },
      ),
    );
  }

  /// Runs [query] through the native async request lifecycle, polling until it
  /// completes or [timeout] elapses. On timeout the request is cancelled and
  /// the connection quarantined. Only a confirmed terminal request is freed.
  Future<Result<QueryResult>> runNativeAsyncQueryWithTimeout({
    required String connectionId,
    required String query,
    required Duration timeout,
    OdbcInFlightExecutionRegistry? inFlightRegistry,
    String? inFlightRequestId,
    String? inFlightExecutionId,
  }) async {
    final generation = _generation;
    final deadline = DateTime.now().add(timeout);
    final startResult = await _service
        .executeAsyncStart(
          connectionId,
          query,
        )
        .timeout(timeout);
    if (startResult.isError()) {
      return Failure(startResult.exceptionOrNull()!);
    }

    final requestId = startResult.getOrThrow();
    if (inFlightRegistry != null && inFlightRequestId != null && inFlightRequestId.isNotEmpty) {
      inFlightRegistry.bindAsyncRequest(
        inFlightRequestId,
        requestId,
        executionId: inFlightExecutionId,
      );
    }
    var completionUnconfirmed = true;

    try {
      while (true) {
        final pollResult = await _service.asyncPoll(requestId);
        if (pollResult.isError()) {
          final pollError = pollResult.exceptionOrNull()!;
          final recovered = await _recoverTerminalAsyncPoll(requestId, pollError);
          if (recovered != null) {
            completionUnconfirmed = false;
            return recovered;
          }
          return Failure(pollError);
        }

        final status = pollResult.getOrThrow();
        switch (status) {
          case _asyncRequestReadyStatus:
            completionUnconfirmed = false;
            final result = await _service.asyncGetResult(requestId);
            return await result.fold(Success.new, Failure.new);
          case _asyncRequestPendingStatus:
            final remaining = deadline.difference(DateTime.now());
            if (remaining <= Duration.zero) {
              completionUnconfirmed = true;
              await _cancelAsyncRequestForTimeout(
                connectionId: connectionId,
                requestId: requestId,
              );
              throw QueryError(
                message: 'Async SQL execution deadline exceeded',
                details: OdbcErrorDetails(
                  code: OdbcErrorCode.timeout,
                  operation: 'executeAsync',
                  connectionId: connectionId,
                  requestId: requestId,
                  outcomeUnknown: true,
                ),
              );
            }
            final delay = remaining < _asyncRequestPollInterval ? remaining : _asyncRequestPollInterval;
            await Future<void>.delayed(delay);
            continue;
          case _asyncRequestErrorStatus:
          case _asyncRequestCancelledStatus:
            completionUnconfirmed = false;
            final result = await _service.asyncGetResult(requestId);
            if (result.isError()) {
              return Failure(result.exceptionOrNull()!);
            }
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Async SQL request completed with status $status without error payload',
                context: {
                  'reason': OdbcContextConstants.asyncRequestNoErrorPayloadReason,
                  'async_status': status,
                  'operation': 'async_get_result',
                },
              ),
            );
          default:
            return Failure(
              domain.QueryExecutionFailure.withContext(
                message: 'Unexpected async SQL request status: $status',
                context: {
                  'reason': OdbcContextConstants.asyncRequestUnexpectedStatusReason,
                  'async_status': status,
                  'operation': 'async_poll',
                },
              ),
            );
        }
      }
    } finally {
      if (!completionUnconfirmed && generation == _generation) {
        await _freeAsyncRequestSafely(requestId);
      } else {
        if (generation == _generation) _markConnectionForDiscard(connectionId);
        _metrics.store.incrementEventCounter('odbc_cleanup_unconfirmed');
      }
    }
  }

  Future<void> abortPreparedStatement({
    required String connectionId,
    required int statementId,
  }) async {
    final cancelResult = await _service.cancelStatement(
      connectionId,
      statementId,
    );
    if (cancelResult.isSuccess()) {
      _metrics.recordTimeoutCancelSuccess();
      return;
    }

    if (OdbcErrorInspector.code(cancelResult.exceptionOrNull()!) == OdbcErrorCode.unsupported) {
      _metrics.store.incrementEventCounter('timeout_cancel_unsupported');
    }

    _markConnectionForDiscard(connectionId);
    _metrics.recordTimeoutCancelFailure();
    developer.log(
      'Failed to cancel prepared statement after abort',
      name: 'database_gateway',
      level: 900,
      error: cancelResult.exceptionOrNull(),
    );
  }

  Future<void> abortAsyncRequest({
    required String connectionId,
    required int requestId,
  }) async {
    _markConnectionForDiscard(connectionId);
    final cancelResult = await _service.asyncCancel(requestId);
    if (cancelResult.isSuccess()) {
      _metrics.recordTimeoutCancelSuccess();
      return;
    }

    _metrics.recordTimeoutCancelFailure();
    developer.log(
      'Failed to cancel async SQL request after abort',
      name: 'database_gateway',
      level: 900,
      error: cancelResult.exceptionOrNull(),
    );
  }

  Future<void> abortInFlightHandle(OdbcInFlightExecutionHandle handle) async {
    final statementId = handle.statementId;
    if (statementId != null) {
      await abortPreparedStatement(
        connectionId: handle.connectionId,
        statementId: statementId,
      );
    }

    final asyncRequestId = handle.asyncRequestId;
    if (asyncRequestId != null) {
      await abortAsyncRequest(
        connectionId: handle.connectionId,
        requestId: asyncRequestId,
      );
    }
  }

  Future<void> _cancelPreparedStatementForTimeout({
    required String connectionId,
    required int statementId,
  }) => abortPreparedStatement(connectionId: connectionId, statementId: statementId);

  Future<void> _cancelAsyncRequestForTimeout({
    required String connectionId,
    required int requestId,
  }) => abortAsyncRequest(connectionId: connectionId, requestId: requestId);

  /// `odbc_fast` reports a finished statement (`asyncPoll` status < 0) as a
  /// failed poll. The engine diagnostic is on the result, not on that poll
  /// error. Recover it so a confirmed SQL failure can release the connection
  /// instead of quarantining the pool.
  Future<Result<QueryResult>?> _recoverTerminalAsyncPoll(
    int requestId,
    Object pollError,
  ) async {
    if (OdbcErrorInspector.outcomeUnknown(pollError)) {
      return null;
    }
    final recovered = await _service.asyncGetResult(requestId);
    if (recovered.isSuccess()) {
      return recovered;
    }
    final recoveredError = recovered.exceptionOrNull()!;
    if (!_isGenericAsyncCompletionFailure(recoveredError)) {
      return Failure(recoveredError);
    }
    if (!_isGenericAsyncCompletionFailure(pollError)) {
      return Failure(pollError is Exception ? pollError : Exception(pollError.toString()));
    }
    return null;
  }

  bool _isGenericAsyncCompletionFailure(Object error) {
    if (error is! OdbcError) {
      return false;
    }
    final message = error.message.trim();
    if (!message.startsWith('Failed to complete async')) {
      return false;
    }
    final sqlState = error.sqlState?.trim();
    if (sqlState != null && sqlState.isNotEmpty) {
      return false;
    }
    return error.nativeCode == null;
  }

  Future<void> _freeAsyncRequestSafely(int requestId) async {
    final freeResult = await _service.asyncFree(requestId);
    if (freeResult.isSuccess()) {
      return;
    }

    developer.log(
      'Failed to free async SQL request after completion',
      name: 'database_gateway',
      level: 900,
      error: freeResult.exceptionOrNull(),
    );
  }
}
