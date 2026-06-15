import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_emitter.dart';

void main() {
  group('OdbcColumnarStreamChunkEmitter', () {
    test('wire-only emits columnar payload without row materialization', () async {
      final result = toTypedColumnar(
        const QueryResult(
          columns: ['id', 'name'],
          rows: [
            [1, 'a'],
            [2, 'b'],
          ],
          rowCount: 2,
        ),
      );
      final rowChunks = <List<Map<String, dynamic>>>[];
      final wireChunks = <StreamingWireChunk>[];

      await OdbcColumnarStreamChunkEmitter.emit(
        result: result,
        fetchSize: 1,
        onChunk: (chunk) async => rowChunks.add(chunk),
        onWireChunk: (chunk) async => wireChunks.add(chunk),
        includeColumnarWire: true,
        wireOnly: true,
      );

      expect(rowChunks, isEmpty);
      expect(wireChunks, hasLength(1));
      expect(wireChunks.first.rows, isEmpty);
      expect(wireChunks.first.columnar, isNotNull);
      expect(wireChunks.first.columnar!['row_count'], 2);
    });

    test('hybrid columnar wire still materializes row maps', () async {
      final result = toTypedColumnar(
        const QueryResult(
          columns: ['id'],
          rows: [
            [1],
            [2],
          ],
          rowCount: 2,
        ),
      );
      final wireChunks = <StreamingWireChunk>[];

      await OdbcColumnarStreamChunkEmitter.emit(
        result: result,
        fetchSize: 1,
        onChunk: (_) async {},
        onWireChunk: (chunk) async => wireChunks.add(chunk),
        includeColumnarWire: true,
      );

      expect(wireChunks, hasLength(2));
      expect(wireChunks.first.rows, isNotEmpty);
      expect(wireChunks.first.columnar, isNotNull);
      expect(wireChunks.last.columnar, isNull);
    });
  });
}
