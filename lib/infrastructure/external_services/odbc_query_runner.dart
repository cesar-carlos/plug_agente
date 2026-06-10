import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_query_response_factory.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_result_encoding_executor.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_statement_executor.dart';
import 'package:plug_agente/infrastructure/external_services/query_execution_outcome.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Executes a single ODBC query/command, selecting the appropriate timeout
/// strategy (prepared-statement timeout, native async, or `.timeout()` guard)
/// and producing a [QueryExecutionOutcome].
///
/// Extracted from `OdbcDatabaseGateway` to isolate the per-execution runner
/// logic from the higher-level acquire/release/retry orchestration. The
/// connection-discard signal is injected to keep this unit decoupled from the
/// connection manager.
final class OdbcQueryRunner {
  OdbcQueryRunner({
    required OdbcService service,
    required MetricsCollector metrics,
    required OdbcStatementExecutor statementExecutor,
    required OdbcResultEncodingExecutor resultEncodingExecutor,
    required void Function(String connectionId) markConnectionForDiscard,
  }) : _service = service,
       _metrics = metrics,
       _statementExecutor = statementExecutor,
       _resultEncodingExecutor = resultEncodingExecutor,
       _markConnectionForDiscard = markConnectionForDiscard;

  final OdbcService _service;
  final MetricsCollector _metrics;
  final OdbcStatementExecutor _statementExecutor;
  final OdbcResultEncodingExecutor _resultEncodingExecutor;
  final void Function(String connectionId) _markConnectionForDiscard;

  /// Stable cache key for a prepared statement (sql + sorted parameter names).
  static String preparedStatementKeyFor(
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    final parameterNames = List<String>.of(
      preparedExecution.parameters?.keys ?? const <String>[],
    );
    parameterNames.sort();
    return '${preparedExecution.sql}::${parameterNames.join(',')}';
  }

  /// Set of prepared-statement keys that occur more than once across [commands]
  /// (worth caching/reusing within a batch).
  static Set<String> collectRepeatedPreparedKeys(List<SqlCommand> commands) {
    final counts = <String, int>{};
    for (final command in commands) {
      final key = preparedStatementKeyFor(
        OdbcPreparedQueryExecution(
          sql: command.sql,
          parameters: command.params,
        ),
      );
      counts[key] = (counts[key] ?? 0) + 1;
    }

    return counts.entries.where((entry) => entry.value > 1).map((entry) => entry.key).toSet();
  }

  /// Runs [preparedExecution] applying the best available timeout strategy.
  Future<QueryExecutionOutcome> runWithTimeout({
    required String connId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required String connectionString,
    Duration? timeout,
    bool preferPreparedTimeout = true,
    String executionMode = 'pooled',
    CancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      return const QueryExecutionOutcome.failure(
        CancellationException('Operation was cancelled'),
      );
    }

    final stopwatch = Stopwatch()..start();
    final usesMultiResultExecution = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
      request,
      preparedExecution,
    );
    final usesPreparedTimeout = _shouldUsePreparedTimeoutPath(
      preparedExecution: preparedExecution,
      timeout: timeout,
      preferPreparedTimeout: preferPreparedTimeout,
      usesMultiResultExecution: usesMultiResultExecution,
    );
    var timeoutCleanupAlreadyHandled = false;
    try {
      if (usesPreparedTimeout) {
        return await _guardWithCooperativeCancellation(
          () => runPrepared(
            connectionId: connId,
            request: request,
            preparedExecution: preparedExecution,
            timeout: timeout,
          ),
          cancellationToken: cancellationToken,
          timeout: timeout,
        );
      }

      if (timeout != null && !usesMultiResultExecution && !_hasNamedParameters(preparedExecution)) {
        final startedAt = DateTime.now();
        try {
          final asyncResult = await _guardWithCooperativeCancellation(
            () => _statementExecutor.runNativeAsyncQueryWithTimeout(
              connectionId: connId,
              query: preparedExecution.sql,
              timeout: timeout,
            ),
            cancellationToken: cancellationToken,
          );
          if (asyncResult.isSuccess()) {
            return QueryExecutionOutcome.success(
              OdbcQueryResponseFactory.fromSingleResult(request, asyncResult.getOrThrow(), startedAt: startedAt),
            );
          }

          final asyncError = asyncResult.exceptionOrNull();
          if (asyncError is! UnsupportedFeatureError) {
            return QueryExecutionOutcome.failure(asyncError);
          }
        } on TimeoutException {
          timeoutCleanupAlreadyHandled = true;
          rethrow;
        }
      }

      return await _guardWithCooperativeCancellation(
        () => _run(connId, request, preparedExecution),
        cancellationToken: cancellationToken,
        timeout: timeout,
      );
    } on TimeoutException catch (error) {
      _metrics.recordQueryTimeout();
      _metrics.recordOdbcQueryTimeoutByStage('query');
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: RpcSqlBudgetConstants.queryTimeoutReason,
      );
      if (!usesPreparedTimeout && !timeoutCleanupAlreadyHandled) {
        await _cancelConnectionForTimeout(connId);
      }
      developer.log(
        'SQL query timed out before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      rethrow;
    } on CancellationException catch (error) {
      if (!usesPreparedTimeout) {
        await _cancelConnectionForTimeout(connId);
      }
      developer.log(
        'SQL query cancelled cooperatively before completion',
        name: 'database_gateway',
        level: 900,
        error: error,
      );
      return QueryExecutionOutcome.failure(error);
    } finally {
      stopwatch.stop();
      _metrics.recordSqlExecutionTime(
        stopwatch.elapsed,
        mode: executionMode,
      );
    }
  }

  /// Runs a single batch command via a (possibly reused) prepared statement
  /// held in the caller-owned [preparedStatements] cache.
  Future<QueryExecutionOutcome> runPreparedBatch({
    required String connectionId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required Map<String, int> preparedStatements,
    required String statementKey,
    Duration? timeout,
  }) async {
    final deadline = OdbcExecutionDeadline.deadlineFor(timeout);
    final stmtId = await _statementExecutor.getOrPrepareStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      preparedStatements: preparedStatements,
      statementKey: statementKey,
      timeout: OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
    );
    if (stmtId.isError()) {
      return QueryExecutionOutcome.failure(
        stmtId.exceptionOrNull() ?? StateError('prepare_statement_failed'),
      );
    }

    final preparedStatementId = stmtId.getOrThrow();
    final startedAt = DateTime.now();
    final result = await _statementExecutor.executePreparedStatementWithTimeout(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      statementId: preparedStatementId,
      timeout: OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
    );
    return result.fold(
      (queryResult) => QueryExecutionOutcome.success(
        OdbcQueryResponseFactory.fromSingleResult(request, queryResult, startedAt: startedAt),
      ),
      QueryExecutionOutcome.failure,
    );
  }

  /// Runs a query through a one-shot prepared statement that is closed after
  /// execution.
  Future<QueryExecutionOutcome> runPrepared({
    required String connectionId,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    Duration? timeout,
  }) async {
    final deadline = OdbcExecutionDeadline.deadlineFor(timeout);
    final preparedStatements = <String, int>{};
    final statementKey = preparedStatementKeyFor(preparedExecution);
    try {
      final stmtId = await _statementExecutor.getOrPrepareStatement(
        connectionId: connectionId,
        preparedExecution: preparedExecution,
        preparedStatements: preparedStatements,
        statementKey: statementKey,
        timeout: OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
      );
      if (stmtId.isError()) {
        return QueryExecutionOutcome.failure(
          stmtId.exceptionOrNull() ?? StateError('prepare_statement_failed'),
        );
      }

      final startedAt = DateTime.now();
      final result = await _statementExecutor.executePreparedStatementWithTimeout(
        connectionId: connectionId,
        preparedExecution: preparedExecution,
        statementId: stmtId.getOrThrow(),
        timeout: OdbcExecutionDeadline.remainingFromDeadline(deadline) ?? timeout,
      );
      return result.fold(
        (queryResult) => QueryExecutionOutcome.success(
          OdbcQueryResponseFactory.fromSingleResult(request, queryResult, startedAt: startedAt),
        ),
        QueryExecutionOutcome.failure,
      );
    } finally {
      await _statementExecutor.closePreparedStatements(
        connectionId,
        preparedStatements.values,
      );
    }
  }

  Future<QueryExecutionOutcome> _run(
    String connectionId,
    QueryRequest request,
    OdbcPreparedQueryExecution preparedExecution,
  ) async {
    if (OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
      request,
      preparedExecution,
    )) {
      final startedAt = DateTime.now();
      final queryResult = await _service.executeQueryMultiFull(
        connectionId,
        preparedExecution.sql,
      );
      return queryResult.fold(
        (success) => QueryExecutionOutcome.success(
          OdbcQueryResponseFactory.fromMultiResult(request, success, startedAt: startedAt),
        ),
        QueryExecutionOutcome.failure,
      );
    }

    final startedAt = DateTime.now();
    final queryResult = await _resultEncodingExecutor.execute(
      connectionId,
      preparedExecution,
    );

    return queryResult.fold(
      (success) => QueryExecutionOutcome.success(
        OdbcQueryResponseFactory.fromSingleResult(request, success, startedAt: startedAt),
      ),
      QueryExecutionOutcome.failure,
    );
  }

  bool _shouldUsePreparedTimeoutPath({
    required OdbcPreparedQueryExecution preparedExecution,
    required Duration? timeout,
    required bool preferPreparedTimeout,
    required bool usesMultiResultExecution,
  }) {
    return timeout != null &&
        preferPreparedTimeout &&
        !usesMultiResultExecution &&
        _hasNamedParameters(preparedExecution);
  }

  bool _hasNamedParameters(OdbcPreparedQueryExecution preparedExecution) {
    return preparedExecution.parameters?.isNotEmpty ?? false;
  }

  Future<void> _cancelConnectionForTimeout(String connectionId) async {
    _markConnectionForDiscard(connectionId);
    _metrics.recordTimeoutCancelFailure();
    developer.log(
      'SQL query timed out; connection marked for discard because no statement handle is available to cancel',
      name: 'database_gateway',
      level: 900,
    );
  }

  Future<T> _guardWithCooperativeCancellation<T>(
    Future<T> Function() operation, {
    CancellationToken? cancellationToken,
    Duration? timeout,
  }) async {
    if (cancellationToken == null) {
      final work = operation();
      return timeout == null ? work : work.timeout(timeout);
    }

    if (cancellationToken.isCancelled) {
      throw const CancellationException('Operation was cancelled');
    }

    var work = operation();
    if (timeout != null) {
      work = work.timeout(timeout);
    }

    return Future.any(<Future<T>>[
      work,
      _waitForCooperativeCancellation(cancellationToken),
    ]);
  }

  Future<T> _waitForCooperativeCancellation<T>(CancellationToken cancellationToken) async {
    while (!cancellationToken.isCancelled) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw const CancellationException('Operation was cancelled');
  }
}
