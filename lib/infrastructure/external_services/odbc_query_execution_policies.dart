import 'dart:async';

import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/errors/odbc_error_inspector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';

/// Shared cancel, timeout, multi-result, and ODBC error helpers for query execution.
abstract final class OdbcQueryExecutionPolicies {
  static const int multiResultSqlLogPreviewChars = 120;
  static final RegExp _previewSqlWhitespaceCollapse = RegExp(r'\s+');

  static String previewSqlForLog(String sql) {
    final collapsed = sql.replaceAll(_previewSqlWhitespaceCollapse, ' ').trim();
    if (collapsed.length <= multiResultSqlLogPreviewChars) {
      return collapsed;
    }
    return '${collapsed.substring(0, multiResultSqlLogPreviewChars)}…';
  }

  static domain.QueryExecutionFailure? cooperativeCancelFailure({
    required QueryRequest request,
    CancellationToken? cancellationToken,
  }) {
    if (cancellationToken?.isCancelled ?? false) {
      return domain.QueryExecutionFailure.withContext(
        message: 'SQL execution cancelled',
        context: {
          'query_id': request.id,
          'reason': OdbcContextConstants.executionCancelledReason,
          'cooperative_cancel': true,
        },
      );
    }
    return null;
  }

  static bool isVacuousMultiResultResponse(
    QueryRequest request,
    QueryResponse response,
  ) {
    if (!request.expectMultipleResults) {
      return false;
    }
    final hasRows =
        response.data.isNotEmpty || response.resultSets.any((QueryResultSet resultSet) => resultSet.rows.isNotEmpty);
    final hasNonZeroRowCount = response.items.any(
      (QueryResponseItem item) => item.isRowCount && (item.rowCount ?? 0) > 0,
    );
    return !hasRows && !hasNonZeroRowCount;
  }

  static bool isInvalidConnectionIdError(Object error) => OdbcErrorInspector.isInvalidConnectionId(error);

  static bool looksLikeTimeoutError(Object error) => OdbcErrorInspector.isTimeout(error);

  static String odbcErrorMessage(Object error) => OdbcErrorInspector.message(error);

  static domain.Failure mapCancellationFailure({
    required Object error,
    required String operation,
    required QueryRequest request,
  }) {
    return OdbcFailureMapper.mapQueryError(
      error,
      operation: operation,
      context: {'query_id': request.id, 'cooperative_cancel': true},
    );
  }

  static domain.QueryExecutionFailure mapTimeoutFailure({
    required TimeoutException error,
    Duration? timeout,
  }) {
    return domain.QueryExecutionFailure.withContext(
      message: 'SQL execution timeout',
      cause: error,
      context: {
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
        if (timeout != null) 'timeout_ms': timeout.inMilliseconds,
      },
    );
  }
}
