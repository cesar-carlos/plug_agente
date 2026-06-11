import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_rpc_materialized_streaming_executor.dart';
import 'package:plug_agente/application/rpc/sql_rpc_stream_terminal_emitter.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

class _RecordingStreamEmitter implements IRpcStreamEmitter {
  final List<RpcStreamChunk> chunks = <RpcStreamChunk>[];

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    chunks.add(chunk);
    return true;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {}
}

void main() {
  group('SqlRpcMaterializedStreamingExecutor', () {
    late SqlRpcMaterializedStreamingExecutor executor;
    late _RecordingStreamEmitter streamEmitter;

    setUp(() {
      streamEmitter = _RecordingStreamEmitter();
      executor = const SqlRpcMaterializedStreamingExecutor(
        terminalEmitter: SqlRpcStreamTerminalEmitter(),
      );
    });

    test('should include column_metadata only on chunk 0', () async {
      const columnMetadata = <Map<String, dynamic>>[
        {'name': 'id', 'type': 'int'},
        {'name': 'name', 'type': 'string'},
      ];
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: <String, dynamic>{'sql': 'SELECT * FROM users'},
      );
      final queryRequest = QueryRequest(
        id: 'q-1',
        agentId: 'agent-1',
        query: 'SELECT * FROM users',
        timestamp: DateTime.utc(2026, 6, 11),
      );
      final normalized = QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [],
        columnMetadata: columnMetadata,
        timestamp: DateTime.utc(2026, 6, 11, 0, 0, 1),
      );
      final limitedRows = List<Map<String, dynamic>>.generate(
        5,
        (index) => <String, dynamic>{'id': index, 'name': 'user$index'},
      );

      await executor.streamMaterializedResult(
        request: request,
        queryRequest: queryRequest,
        normalized: normalized,
        limitedRows: limitedRows,
        effectiveMaxRows: 100,
        wasTruncated: false,
        limits: const TransportLimits(streamingChunkSize: 2),
        streamEmitter: streamEmitter,
      );

      expect(streamEmitter.chunks, hasLength(3));
      expect(streamEmitter.chunks[0].chunkIndex, 0);
      expect(streamEmitter.chunks[0].columnMetadata, columnMetadata);
      expect(streamEmitter.chunks[1].chunkIndex, 1);
      expect(streamEmitter.chunks[1].columnMetadata, isNull);
      expect(streamEmitter.chunks[2].chunkIndex, 2);
      expect(streamEmitter.chunks[2].columnMetadata, isNull);
    });
  });
}
