import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';

/// Maps a [QueryResponse] domain entity to the JSON-RPC wire format consumed
/// by the Socket.IO transport client.
///
/// Separating this mapping from the transport client keeps [QueryResponse]
/// structure changes out of the transport layer (SRP).
abstract final class QueryResponseRpcMapper {
  /// Converts [response] to the `result` map sent inside `rpc:response`.
  ///
  /// Uses [QueryResponse.startedAt] for `started_at` when available; falls
  /// back to [QueryResponse.timestamp] when start tracking is absent (legacy).
  static Map<String, dynamic> toRpcResult(QueryResponse response) {
    final finishedAt = response.timestamp;
    final startedAt = response.startedAt ?? finishedAt;

    final result = <String, dynamic>{
      'execution_id': response.id,
      'started_at': startedAt.toUtc().toIso8601String(),
      'finished_at': finishedAt.toUtc().toIso8601String(),
      'rows': response.data,
      'row_count': response.data.length,
      if (response.wasTruncated) 'truncated': true,
      if (response.columnMetadata != null) 'column_metadata': response.columnMetadata,
      if (response.hasMultiResult) ...{
        'multi_result': true,
        'result_set_count': response.resultSets.length,
        'item_count': response.items.length,
        'result_sets': response.resultSets.map(_resultSetToRpcMap).toList(growable: false),
        'items': response.items.map(_responseItemToRpcMap).toList(growable: false),
      },
      if (response.pagination != null)
        'pagination': {
          'page': response.pagination!.page,
          'page_size': response.pagination!.pageSize,
          'returned_rows': response.pagination!.returnedRows,
          'has_next_page': response.pagination!.hasNextPage,
          'has_previous_page': response.pagination!.hasPreviousPage,
          if (response.pagination!.currentCursor != null) 'current_cursor': response.pagination!.currentCursor,
          if (response.pagination!.nextCursor != null) 'next_cursor': response.pagination!.nextCursor,
        },
    };
    RpcWireMap.putOptionalInt(result, 'affected_rows', response.affectedRows);
    return result;
  }

  static Map<String, dynamic> _resultSetToRpcMap(QueryResultSet resultSet) {
    final map = <String, dynamic>{
      'index': resultSet.index,
      'rows': resultSet.rows,
      'row_count': resultSet.rowCount,
      if (resultSet.columnMetadata != null) 'column_metadata': resultSet.columnMetadata,
    };
    RpcWireMap.putOptionalInt(map, 'affected_rows', resultSet.affectedRows);
    return map;
  }

  static Map<String, dynamic> _responseItemToRpcMap(QueryResponseItem item) {
    if (item.resultSet != null) {
      final resultSet = item.resultSet!;
      final map = <String, dynamic>{
        'type': 'result_set',
        'index': item.index,
        'result_set_index': resultSet.index,
        'rows': resultSet.rows,
        'row_count': resultSet.rowCount,
        if (resultSet.columnMetadata != null) 'column_metadata': resultSet.columnMetadata,
      };
      RpcWireMap.putOptionalInt(map, 'affected_rows', resultSet.affectedRows);
      return map;
    }
    final map = <String, dynamic>{
      'type': 'row_count',
      'index': item.index,
    };
    RpcWireMap.putOptionalInt(map, 'affected_rows', item.rowCount);
    return map;
  }

  /// Builds the full [RpcResponse] (success or error) for a [QueryResponse].
  static RpcResponse toRpcResponse(QueryResponse response) {
    if (response.error != null) {
      return RpcResponse.error(
        id: response.requestId,
        error: RpcError(
          code: RpcErrorCode.sqlExecutionFailed,
          message: RpcErrorCode.getMessage(RpcErrorCode.sqlExecutionFailed),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.sqlExecutionFailed,
            technicalMessage: response.error!,
            correlationId: response.requestId,
          ),
        ),
      );
    }
    return RpcResponse.success(
      id: response.requestId,
      result: toRpcResult(response),
    );
  }
}
