import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
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

  static const int _maxPreparedStatementsPerConnection = 64;
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
  }) async {
    final existingStmtId = preparedStatements[statementKey];
    if (existingStmtId != null) {
      preparedStatements.remove(statementKey);
      preparedStatements[statementKey] = existingStmtId;
      _metrics.recordPreparedStatementReuse();
      return Success(existingStmtId);
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

    return prepareResult.fold(
      (stmtId) {
        if (preparedStatements.length >= _maxPreparedStatementsPerConnection) {
          final oldestKey = preparedStatements.keys.first;
          final oldestStmtId = preparedStatements.remove(oldestKey);
          if (oldestStmtId != null) {
            unawaited(closePreparedStatements(connectionId, <int>[oldestStmtId]));
          }
        }
        preparedStatements[statementKey] = stmtId;
        return Success(stmtId);
      },
      Failure.new,
    );
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

    return _service.executePrepared(
      connectionId,
      stmtId,
      null,
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
  }) async {
    final statementOptions = timeout == null ? null : StatementOptions(timeout: timeout);
    final execution = _executePreparedStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      stmtId: statementId,
      options: statementOptions,
    );
    if (timeout == null) {
      return execution;
    }

    return execution.timeout(
      timeout,
      onTimeout: () async {
        _markConnectionForDiscard(connectionId);
        unawaited(
          _cancelPreparedStatementForTimeout(
            connectionId: connectionId,
            statementId: statementId,
          ),
        );
        throw TimeoutException('Prepared statement execution deadline exceeded');
      },
    );
  }

  Future<void> closePreparedStatements(
    String connectionId,
    Iterable<int> stmtIds,
  ) async {
    for (final stmtId in stmtIds) {
      try {
        await _service.closeStatement(connectionId, stmtId);
      } on Object catch (error) {
        developer.log(
          'Failed to close prepared statement after execution',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      }
    }
  }

  /// Runs [query] through the native async request lifecycle, polling until it
  /// completes or [timeout] elapses. On timeout the request is cancelled and
  /// the connection marked for discard; the request is always freed.
  Future<Result<QueryResult>> runNativeAsyncQueryWithTimeout({
    required String connectionId,
    required String query,
    required Duration timeout,
  }) async {
    final startResult = await _service.executeAsyncStart(
      connectionId,
      query,
    );
    if (startResult.isError()) {
      return Failure(startResult.exceptionOrNull()!);
    }

    final requestId = startResult.getOrThrow();
    final deadline = DateTime.now().add(timeout);

    try {
      while (true) {
        final pollResult = await _service.asyncPoll(requestId);
        if (pollResult.isError()) {
          return Failure(pollResult.exceptionOrNull()!);
        }

        final status = pollResult.getOrThrow();
        switch (status) {
          case _asyncRequestReadyStatus:
            final result = await _service.asyncGetResult(requestId);
            return result.fold(Success.new, Failure.new);
          case _asyncRequestPendingStatus:
            final remaining = deadline.difference(DateTime.now());
            if (remaining <= Duration.zero) {
              await _cancelAsyncRequestForTimeout(
                connectionId: connectionId,
                requestId: requestId,
              );
              throw TimeoutException('Async SQL execution deadline exceeded');
            }
            final delay = remaining < _asyncRequestPollInterval ? remaining : _asyncRequestPollInterval;
            await Future<void>.delayed(delay);
            continue;
          case _asyncRequestErrorStatus:
          case _asyncRequestCancelledStatus:
            final result = await _service.asyncGetResult(requestId);
            if (result.isError()) {
              return Failure(result.exceptionOrNull()!);
            }
            return Failure(
              Exception(
                'Async SQL request completed with status $status without error payload',
              ),
            );
          default:
            return Failure(
              Exception('Unexpected async SQL request status: $status'),
            );
        }
      }
    } finally {
      await _freeAsyncRequestSafely(requestId);
    }
  }

  Future<void> _cancelPreparedStatementForTimeout({
    required String connectionId,
    required int statementId,
  }) async {
    final cancelResult = await _service.cancelStatement(
      connectionId,
      statementId,
    );
    cancelResult.fold(
      (_) {
        _metrics.recordTimeoutCancelSuccess();
      },
      (error) {
        _markConnectionForDiscard(connectionId);
        _metrics.recordTimeoutCancelFailure();
        developer.log(
          'Failed to cancel prepared statement after timeout',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      },
    );
  }

  Future<void> _cancelAsyncRequestForTimeout({
    required String connectionId,
    required int requestId,
  }) async {
    _markConnectionForDiscard(connectionId);
    final cancelResult = await _service.asyncCancel(requestId);
    cancelResult.fold(
      (_) {
        _metrics.recordTimeoutCancelSuccess();
      },
      (error) {
        _metrics.recordTimeoutCancelFailure();
        developer.log(
          'Failed to cancel async SQL request after timeout',
          name: 'database_gateway',
          level: 900,
          error: error,
        );
      },
    );
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
