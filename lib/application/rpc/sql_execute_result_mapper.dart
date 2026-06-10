import 'package:plug_agente/application/rpc/sql_pagination_resolver.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';

class SqlExecuteResultMapper {
  const SqlExecuteResultMapper();

  /// Hub-facing execution timestamps must both be UTC ISO-8601 (with `Z` offset).
  static String executionTimestampUtcIso(DateTime timestamp) {
    return timestamp.toUtc().toIso8601String();
  }

  Map<String, dynamic> buildExecuteResultData(
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
      'started_at': executionTimestampUtcIso(startedAt),
      'finished_at': executionTimestampUtcIso(finishedAt),
      'sql_handling_mode': sqlHandlingMode.name,
      'max_rows_handling': 'response_truncation',
      'effective_max_rows': effectiveMaxRows,
      'rows': limitedRows,
      'row_count': limitedRows.length,
    };

    RpcWireMap.putOptionalInt(resultData, 'affected_rows', response.affectedRows);
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
      resultData['result_sets'] = response.resultSets.map(buildResultSetPayload).toList(growable: false);
      resultData['items'] = response.items.map(buildResponseItemPayload).toList(growable: false);
    }

    return resultData;
  }

  Map<String, dynamic> buildResultSetPayload(
    QueryResultSet resultSet, {
    bool includeIndex = true,
  }) {
    final payload = <String, dynamic>{
      if (includeIndex) 'index': resultSet.index,
      'rows': resultSet.rows,
      'row_count': resultSet.rowCount,
      if (resultSet.columnMetadata != null) 'column_metadata': resultSet.columnMetadata,
    };
    RpcWireMap.putOptionalInt(payload, 'affected_rows', resultSet.affectedRows);
    return payload;
  }

  Map<String, dynamic> buildResponseItemPayload(QueryResponseItem item) {
    if (item.resultSet != null) {
      return {
        'type': 'result_set',
        'index': item.index,
        'result_set_index': item.resultSet!.index,
        ...buildResultSetPayload(item.resultSet!, includeIndex: false),
      };
    }
    final payload = <String, dynamic>{
      'type': 'row_count',
      'index': item.index,
    };
    RpcWireMap.putOptionalInt(payload, 'affected_rows', item.rowCount);
    return payload;
  }

  QueryResponse applyMaxRowsToMultiResultSets(
    QueryResponse response,
    int maxRows,
  ) {
    if (response.resultSets.isEmpty) {
      return response;
    }
    final newSets = <QueryResultSet>[];
    for (final rs in response.resultSets) {
      final limited = truncateSqlResultRows(rs.rows, maxRows);
      newSets.add(
        QueryResultSet(
          index: rs.index,
          rows: limited,
          rowCount: limited.length,
          affectedRows: rs.affectedRows,
          columnMetadata: rs.columnMetadata,
        ),
      );
    }
    final newItems = response.items
        .map((QueryResponseItem item) {
          if (item.resultSet != null) {
            final idx = item.resultSet!.index;
            final match = newSets.firstWhere(
              (QueryResultSet s) => s.index == idx,
            );
            return QueryResponseItem.resultSet(
              index: item.index,
              resultSet: match,
            );
          }
          return item;
        })
        .toList(growable: false);
    final primary = newSets.isNotEmpty ? newSets.first : const QueryResultSet(index: 0, rows: [], rowCount: 0);
    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: primary.rows,
      affectedRows: response.affectedRows,
      startedAt: response.startedAt,
      wasTruncated: response.wasTruncated,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: primary.columnMetadata,
      pagination: response.pagination,
      resultSets: newSets,
      items: newItems,
    );
  }

  bool multiResultSetsWereTruncated(
    QueryResponse before,
    QueryResponse after,
  ) {
    if (before.resultSets.length != after.resultSets.length) {
      return true;
    }
    for (var i = 0; i < before.resultSets.length; i++) {
      if (before.resultSets[i].rows.length != after.resultSets[i].rows.length) {
        return true;
      }
    }
    return false;
  }
}
