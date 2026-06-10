import 'package:plug_agente/application/rpc/sql_execute_result_mapper.dart';
import 'package:plug_agente/application/rpc/sql_pagination_resolver.dart';
import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

class SqlRpcMaterializedStreamingExecutor {
  const SqlRpcMaterializedStreamingExecutor({
    required SqlRpcStreamTerminalEmitter terminalEmitter,
    IRpcDispatchMetricsCollector? dispatchMetrics,
  }) : _terminalEmitter = terminalEmitter,
       _dispatchMetrics = dispatchMetrics;

  final SqlRpcStreamTerminalEmitter _terminalEmitter;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;

  Future<RpcResponse> streamMaterializedResult({
    required RpcRequest request,
    required QueryRequest queryRequest,
    required QueryResponse normalized,
    required List<Map<String, dynamic>> limitedRows,
    required int effectiveMaxRows,
    required bool wasTruncated,
    required TransportLimits limits,
    required IRpcStreamEmitter streamEmitter,
  }) async {
    final streamId = 'stream-${queryRequest.id}';
    final rows = limitedRows;
    final totalChunks = (rows.length / limits.streamingChunkSize).ceil();
    var overflowed = false;

    for (var i = 0; i < rows.length && !overflowed; i += limits.streamingChunkSize) {
      final chunkEnd = i + limits.streamingChunkSize > rows.length
          ? rows.length
          : i + limits.streamingChunkSize;
      final chunkRows = rows.sublist(i, chunkEnd);
      if (!await streamEmitter.emitChunk(
        RpcStreamChunk(
          streamId: streamId,
          requestId: request.id,
          chunkIndex: i ~/ limits.streamingChunkSize,
          rows: chunkRows,
          totalChunks: totalChunks,
          columnMetadata: normalized.columnMetadata,
        ),
      )) {
        overflowed = true;
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    if (!overflowed) {
      _dispatchMetrics?.recordSqlExecuteStreamingChunksResponse();
    }

    if (overflowed) {
      await _terminalEmitter.emitTerminalComplete(
        streamEmitter: streamEmitter,
        streamId: streamId,
        requestId: request.id,
        totalRows: rows.length,
        status: StreamTerminalStatus.aborted,
      );
      return RpcResponse.error(
        id: request.id,
        error: RpcError(
          code: RpcErrorCode.resultTooLarge,
          message: RpcErrorCode.getMessage(RpcErrorCode.resultTooLarge),
          data: RpcErrorCode.buildErrorData(
            code: RpcErrorCode.resultTooLarge,
            technicalMessage:
                'Streaming buffer overflowed: hub not consuming fast enough; '
                'stream cancelled to avoid data loss.',
            correlationId: request.id?.toString(),
            subreason: RpcStreamingConstants.backpressureOverflowReason,
          ),
        ),
      );
    }

    await streamEmitter.emitComplete(
      RpcStreamComplete(
        streamId: streamId,
        requestId: request.id,
        totalRows: rows.length,
        affectedRows: normalized.affectedRows,
        executionId: normalized.id,
        startedAt: SqlExecuteResultMapper.executionTimestampUtcIso(queryRequest.timestamp),
        finishedAt: SqlExecuteResultMapper.executionTimestampUtcIso(normalized.timestamp),
      ),
    );

    final resultData = <String, dynamic>{
      'stream_id': streamId,
      'execution_id': normalized.id,
      'started_at': SqlExecuteResultMapper.executionTimestampUtcIso(queryRequest.timestamp),
      'finished_at': SqlExecuteResultMapper.executionTimestampUtcIso(normalized.timestamp),
      'sql_handling_mode': queryRequest.sqlHandlingMode.name,
      'max_rows_handling': 'response_truncation',
      'effective_max_rows': effectiveMaxRows,
      'rows': <Map<String, dynamic>>[],
      'row_count': 0,
      'returned_rows': rows.length,
      if (wasTruncated) 'truncated': true,
      if (normalized.columnMetadata != null) 'column_metadata': normalized.columnMetadata,
      if (normalized.pagination != null) 'pagination': buildPaginationResult(normalized.pagination!),
    };
    RpcWireMap.putOptionalInt(resultData, 'affected_rows', normalized.affectedRows);

    return RpcResponse.success(id: request.id, result: resultData);
  }
}
