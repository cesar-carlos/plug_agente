import 'dart:async';
import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
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
  }) async {
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
    try {
      if (usesPreparedTimeout) {
        return await runPrepared(
          connectionId: connId,
          request: request,
          preparedExecution: preparedExecution,
          timeout: timeout,
        );
      }

      if (timeout != null && !usesMultiResultExecution && !_hasNamedParameters(preparedExecution)) {
        final startedAt = DateTime.now();
        final asyncResult = await _statementExecutor.runNativeAsyncQueryWithTimeout(
          connectionId: connId,
          query: preparedExecution.sql,
          timeout: timeout,
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
      }

      if (timeout == null) {
        return await _run(connId, request, preparedExecution);
      }

      return await _run(
        connId,
        request,
        preparedExecution,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      _metrics.recordQueryTimeout();
      _metrics.recordOdbcQueryTimeoutByStage('query');
      _metrics.recordDiagnosticReason(
        category: 'timeout',
        reason: RpcSqlBudgetConstants.queryTimeoutReason,
      );
      if (!usesPreparedTimeout) {
        await _cancelConnectionForTimeout(connId);
      }
      developer.log(
        'SQL query timed out before completion',
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
    final deadline = _deadlineFor(timeout);
    final stmtId = await _statementExecutor.getOrPrepareStatement(
      connectionId: connectionId,
      preparedExecution: preparedExecution,
      preparedStatements: preparedStatements,
      statementKey: statementKey,
      timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
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
      timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
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
    final deadline = _deadlineFor(timeout);
    final preparedStatements = <String, int>{};
    final statementKey = preparedStatementKeyFor(preparedExecution);
    try {
      final stmtId = await _statementExecutor.getOrPrepareStatement(
        connectionId: connectionId,
        preparedExecution: preparedExecution,
        preparedStatements: preparedStatements,
        statementKey: statementKey,
        timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
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
        timeout: _remainingTimeoutFromDeadline(deadline) ?? timeout,
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

  DateTime? _deadlineFor(Duration? timeout) {
    return timeout == null ? null : DateTime.now().add(timeout);
  }

  Duration? _remainingTimeoutFromDeadline(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : remaining;
  }
}
