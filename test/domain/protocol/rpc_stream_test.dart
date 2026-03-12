import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_stream.dart';

void main() {
  group('RpcStreamChunk', () {
    test('should serialize and deserialize', () {
      const chunk = RpcStreamChunk(
        streamId: 's-1',
        requestId: 'req-1',
        chunkIndex: 0,
        rows: [
          {'id': 1, 'name': 'a'},
          {'id': 2, 'name': 'b'},
        ],
        totalChunks: 3,
      );

      final json = chunk.toJson();
      expect(json['stream_id'], 's-1');
      expect(json['request_id'], 'req-1');
      expect(json['chunk_index'], 0);
      expect((json['rows'] as List).length, 2);
      expect(json['total_chunks'], 3);

      final restored = RpcStreamChunk.fromJson(json);
      expect(restored.streamId, chunk.streamId);
      expect(restored.chunkIndex, chunk.chunkIndex);
      expect(restored.rows.length, chunk.rows.length);
    });
  });

  group('RpcStreamComplete', () {
    test('should serialize and deserialize', () {
      const complete = RpcStreamComplete(
        streamId: 's-1',
        requestId: 'req-1',
        totalRows: 1000,
        affectedRows: 0,
        executionId: 'exec-1',
      );

      final json = complete.toJson();
      expect(json['stream_id'], 's-1');
      expect(json['total_rows'], 1000);
      expect(json['affected_rows'], 0);
      expect(json['execution_id'], 'exec-1');

      final restored = RpcStreamComplete.fromJson(json);
      expect(restored.streamId, complete.streamId);
      expect(restored.totalRows, complete.totalRows);
    });
  });

  group('RpcStreamPull', () {
    test('should serialize and deserialize with default windowSize', () {
      const pull = RpcStreamPull(streamId: 's-1');

      final json = pull.toJson();
      expect(json['stream_id'], 's-1');
      expect(json['window_size'], 1);

      final restored = RpcStreamPull.fromJson(json);
      expect(restored.streamId, pull.streamId);
      expect(restored.windowSize, 1);
    });

    test('should use custom windowSize', () {
      const pull = RpcStreamPull(streamId: 's-1', windowSize: 5);

      final json = pull.toJson();
      expect(json['window_size'], 5);

      final restored = RpcStreamPull.fromJson({
        'stream_id': 's-1',
        'window_size': 5,
      });
      expect(restored.windowSize, 5);
    });
  });
}
