import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

void main() {
  group('mapOdbcRowToStreamingMap', () {
    test('should map ODBC row vectors into streaming row maps', () {
      final row = mapOdbcRowToStreamingMap(
        const <String>['id', 'name'],
        const <dynamic>[1, 'a'],
      );

      expect(row, <String, dynamic>{'id': 1, 'name': 'a'});
    });
  });

  group('mapQueryRowsToChunks', () {
    test('should emit a single chunk when native batch fits fetch size', () {
      final chunks = mapQueryRowsToChunks(
        const OdbcStreamingChunkMapperInput(
          columns: <String>['id'],
          rows: <List<dynamic>>[
            <dynamic>[1],
            <dynamic>[2],
          ],
          fetchSize: 500,
        ),
      );

      expect(chunks, hasLength(1));
      expect(chunks.single, [
        <String, dynamic>{'id': 1},
        <String, dynamic>{'id': 2},
      ]);
    });

    test('should split rows when native batch exceeds fetch size', () {
      final chunks = mapQueryRowsToChunks(
        const OdbcStreamingChunkMapperInput(
          columns: <String>['id'],
          rows: <List<dynamic>>[
            <dynamic>[1],
            <dynamic>[2],
            <dynamic>[3],
          ],
          fetchSize: 2,
        ),
      );

      expect(chunks, hasLength(2));
      expect(chunks[0].length, 2);
      expect(chunks[1].length, 1);
    });

    test('should return no chunks for empty input', () {
      final chunks = mapQueryRowsToChunks(
        const OdbcStreamingChunkMapperInput(
          columns: <String>['id'],
          rows: <List<dynamic>>[],
          fetchSize: 100,
        ),
      );

      expect(chunks, isEmpty);
    });
  });
}
