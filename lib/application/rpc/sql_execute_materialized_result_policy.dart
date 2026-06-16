import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:result_dart/result_dart.dart';

/// Guards hub `sql.execute` from materializing result sets above safe thresholds.
final class SqlExecuteMaterializedResultPolicy {
  const SqlExecuteMaterializedResultPolicy();

  bool shouldRejectMaterializedPath({
    required int effectiveMaxRows,
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
  }) {
    if (negotiatedExtensions['streamingResults'] != true) {
      return false;
    }

    return exceedsMaterializedThresholds(
      effectiveMaxRows,
      transportMaxRows: limits.maxRows,
    );
  }

  /// Rejects ODBC materialization when streaming was negotiated but DB streaming
  /// was unavailable and the caller expected streaming (explicit or auto policy).
  bool shouldRejectMaterializedOdbcFallback({
    required int effectiveMaxRows,
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    required bool prefersDbStreaming,
  }) {
    if (!isStreamingResultsNegotiated(negotiatedExtensions)) {
      return false;
    }
    return exceedsMaterializedThresholds(
      effectiveMaxRows,
      transportMaxRows: limits.maxRows,
    );
  }

  /// Rejects chunking a fully materialized result when streaming was negotiated.
  bool shouldRejectMaterializedStreamingChunks({
    required int rowCount,
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
  }) {
    if (!isStreamingResultsNegotiated(negotiatedExtensions)) {
      return false;
    }
    return rowCount > limits.streamingRowThreshold;
  }

  bool exceedsMaterializedThresholds(
    int effectiveMaxRows, {
    int? transportMaxRows,
  }) {
    final rowThreshold = ConnectionConstants.sqlExecuteMaterializedMaxRows;
    final byteThreshold = ConnectionConstants.sqlExecuteMaterializedMaxEstimatedBytes;
    final estimatedBytesPerRow = ConnectionConstants.sqlExecuteMaterializedEstimatedBytesPerRow;

    final exceedsRows = effectiveMaxRows >= rowThreshold;
    final exceedsBytes = effectiveMaxRows * estimatedBytesPerRow >= byteThreshold;
    final exceedsTransportMaxRows = transportMaxRows != null &&
        effectiveMaxRows >= transportMaxRows &&
        transportMaxRows >= rowThreshold;

    return exceedsRows || exceedsBytes || exceedsTransportMaxRows;
  }

  /// Playground guard uses strict `>` on row count so the default materialized cap
  /// (equal to [ConnectionConstants.sqlExecuteMaterializedMaxRows]) remains usable.
  bool exceedsPlaygroundMaterializedThresholds(int effectiveMaxRows) {
    final rowThreshold = ConnectionConstants.sqlExecuteMaterializedMaxRows;
    final byteThreshold = ConnectionConstants.sqlExecuteMaterializedMaxEstimatedBytes;
    final estimatedBytesPerRow = ConnectionConstants.sqlExecuteMaterializedEstimatedBytesPerRow;

    final exceedsRows = effectiveMaxRows > rowThreshold;
    final exceedsBytes = effectiveMaxRows * estimatedBytesPerRow > byteThreshold;

    return exceedsRows || exceedsBytes;
  }

  /// Guards Playground materialized mode from unpaginated or oversized page requests.
  Result<void> rejectIfPlaygroundMaterializedUnsafe({
    required String trimmedQuery,
    required bool expectMultipleResults,
    int? pageSize,
  }) {
    if (expectMultipleResults) {
      return const Success(unit);
    }

    if (_queryDeclaresServerSideRowLimit(trimmedQuery)) {
      return const Success(unit);
    }

    final paginationPlan = SqlValidator.validatePaginationQuery(trimmedQuery);
    if (paginationPlan.isSuccess()) {
      final effectiveMaxRows = pageSize ?? ConnectionConstants.sqlExecuteMaterializedMaxRows;
      if (!exceedsPlaygroundMaterializedThresholds(effectiveMaxRows)) {
        return const Success(unit);
      }

      return Failure(
        buildPlaygroundRejectionFailure(
          effectiveMaxRows: effectiveMaxRows,
          unpaginated: false,
        ),
      );
    }

    final effectiveMaxRows = ConnectionConstants.sqlExecuteMaterializedMaxRows;
    if (!exceedsPlaygroundMaterializedThresholds(effectiveMaxRows)) {
      return const Success(unit);
    }

    return Failure(
      buildPlaygroundRejectionFailure(
        effectiveMaxRows: effectiveMaxRows,
        unpaginated: true,
      ),
    );
  }

  bool _queryDeclaresServerSideRowLimit(String query) {
    if (SqlValidator.containsTopLevelPaginationClause(query)) {
      return true;
    }

    return _containsTopLevelSelectTop(query);
  }

  bool _containsTopLevelSelectTop(String query) {
    final normalized = query.trim().replaceFirst(RegExp(r';+\s*$'), '');
    if (normalized.isEmpty) {
      return false;
    }

    return RegExp(
      r'^\s*select\s+top\s+\d+\b',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  domain.QueryExecutionFailure buildPlaygroundRejectionFailure({
    required int effectiveMaxRows,
    required bool unpaginated,
  }) {
    final reason = unpaginated
        ? RpcSqlBudgetConstants.playgroundMaterializedUnpaginatedReason
        : RpcSqlBudgetConstants.materializedResultTooLargeReason;
    final userMessage = unpaginated
        ? 'This query has no server-side pagination. Enable ODBC streaming mode in Playground '
            'or add OFFSET/FETCH pagination for large result sets.'
        : 'This page size may return too many rows for materialized Playground results. '
            'Enable ODBC streaming mode or reduce the page size.';

    return domain.QueryExecutionFailure.withContext(
      message: unpaginated
          ? 'Playground materialized query requires pagination or streaming'
          : 'Playground page size too large for materialized results',
      context: <String, dynamic>{
        'reason': reason,
        'effective_max_rows': effectiveMaxRows,
        'threshold_rows': ConnectionConstants.sqlExecuteMaterializedMaxRows,
        'threshold_estimated_bytes': ConnectionConstants.sqlExecuteMaterializedMaxEstimatedBytes,
        'user_message': userMessage,
        'recommendation': OdbcContextConstants.playgroundMaterializedUseStreamingRecommendation,
        'operation': 'playground_execute_query',
      },
    );
  }

  domain.QueryExecutionFailure buildRejectionFailure({
    required int effectiveMaxRows,
    String? requestId,
  }) {
    final context = <String, dynamic>{
      'reason': RpcSqlBudgetConstants.materializedResultTooLargeReason,
      'rpc_error_code': RpcErrorCode.resultTooLarge,
      'effective_max_rows': effectiveMaxRows,
      'threshold_rows': ConnectionConstants.sqlExecuteMaterializedMaxRows,
      'threshold_estimated_bytes': ConnectionConstants.sqlExecuteMaterializedMaxEstimatedBytes,
      'user_message':
          'This query may return too many rows for a materialized response. '
          'Use database streaming (prefer_db_streaming) or reduce max_rows.',
      'recommendation': OdbcContextConstants.materializedResultUseDbStreamingRecommendation,
    };
    if (requestId != null) {
      context['request_id'] = requestId;
    }

    return domain.QueryExecutionFailure.withContext(
      message: 'Result set too large for materialized sql.execute',
      context: context,
    );
  }

  Result<void> rejectIfMaterializedPathUnsafe({
    required int effectiveMaxRows,
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    String? requestId,
  }) {
    if (!shouldRejectMaterializedPath(
      effectiveMaxRows: effectiveMaxRows,
      limits: limits,
      negotiatedExtensions: negotiatedExtensions,
    )) {
      return const Success(unit);
    }

    return Failure(
      buildRejectionFailure(
        effectiveMaxRows: effectiveMaxRows,
        requestId: requestId,
      ),
    );
  }

  Result<void> rejectIfMaterializedOdbcFallbackUnsafe({
    required int effectiveMaxRows,
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    required bool prefersDbStreaming,
    String? requestId,
  }) {
    if (!shouldRejectMaterializedOdbcFallback(
      effectiveMaxRows: effectiveMaxRows,
      limits: limits,
      negotiatedExtensions: negotiatedExtensions,
      prefersDbStreaming: prefersDbStreaming,
    )) {
      return const Success(unit);
    }

    return Failure(
      buildRejectionFailure(
        effectiveMaxRows: effectiveMaxRows,
        requestId: requestId,
      ),
    );
  }

  Result<void> rejectIfMaterializedStreamingFallbackUnsafe({
    required int rowCount,
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    String? requestId,
  }) {
    if (!shouldRejectMaterializedStreamingChunks(
      rowCount: rowCount,
      limits: limits,
      negotiatedExtensions: negotiatedExtensions,
    )) {
      return const Success(unit);
    }

    return Failure(
      buildRejectionFailure(
        effectiveMaxRows: rowCount,
        requestId: requestId,
      ),
    );
  }
}
