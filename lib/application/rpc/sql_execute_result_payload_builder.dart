import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

/// Builds the `result` object shape for successful `sql.execute` RPC responses.
///
/// Shared with `RpcMethodDispatcher` so payload layout and benchmarks stay aligned.
class SqlExecuteResultPayloadBuilder {
  SqlExecuteResultPayloadBuilder._();

  static Map<String, dynamic> buildPaginationResult(
    QueryPaginationInfo pagination,
  ) {
    return {
      'page': pagination.page,
      'page_size': pagination.pageSize,
      'returned_rows': pagination.returnedRows,
      'has_next_page': pagination.hasNextPage,
      'has_previous_page': pagination.hasPreviousPage,
      if (pagination.currentCursor != null)
        'current_cursor': pagination.currentCursor,
      if (pagination.nextCursor != null) 'next_cursor': pagination.nextCursor,
    };
  }

  static Map<String, dynamic> buildExecuteResultData(
    QueryResponse response, {
    required DateTime startedAt,
    required DateTime finishedAt,
    required List<Map<String, dynamic>> limitedRows,
    required bool wasTruncated,
    required SqlHandlingMode sqlHandlingMode,
    required int effectiveMaxRows,
    bool forceMultiResultEnvelope = false,
  }) {
    final resultData = <String, dynamic>{
      'execution_id': response.id,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
      'sql_handling_mode': sqlHandlingMode.name,
      'max_rows_handling': 'response_truncation',
      'effective_max_rows': effectiveMaxRows,
      'rows': limitedRows,
      'row_count': limitedRows.length,
    };

    if (response.affectedRows != null) {
      resultData['affected_rows'] = response.affectedRows;
    }
    if (wasTruncated) {
      resultData['truncated'] = true;
    }
    if (response.columnMetadata != null) {
      resultData['column_metadata'] = response.columnMetadata;
    }
    if (response.pagination != null) {
      resultData['pagination'] = buildPaginationResult(response.pagination!);
    }
    if (forceMultiResultEnvelope || response.hasMultiResult) {
      resultData['multi_result'] = true;
      resultData['result_set_count'] = response.resultSets.length;
      resultData['item_count'] = response.items.length;
      resultData['result_sets'] = response.resultSets
          .map(buildResultSetPayload)
          .toList(growable: false);
      resultData['items'] = response.items
          .map(buildResponseItemPayload)
          .toList(growable: false);
    }

    return resultData;
  }

  static Map<String, dynamic> buildResultSetPayload(
    QueryResultSet resultSet, {
    bool includeIndex = true,
  }) {
    return {
      if (includeIndex) 'index': resultSet.index,
      'rows': resultSet.rows,
      'row_count': resultSet.rowCount,
      if (resultSet.affectedRows != null)
        'affected_rows': resultSet.affectedRows,
      if (resultSet.columnMetadata != null)
        'column_metadata': resultSet.columnMetadata,
    };
  }

  static Map<String, dynamic> buildResponseItemPayload(QueryResponseItem item) {
    if (item.resultSet != null) {
      return {
        'type': 'result_set',
        'index': item.index,
        'result_set_index': item.resultSet!.index,
        ...buildResultSetPayload(item.resultSet!, includeIndex: false),
      };
    }
    return {
      'type': 'row_count',
      'index': item.index,
      'affected_rows': item.rowCount,
    };
  }
}
