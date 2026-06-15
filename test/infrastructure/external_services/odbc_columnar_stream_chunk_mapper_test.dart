import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

void main() {
  group('mapTypedColumnarToRowMaps', () {
    test('maps typed int32 column without QueryResult materialization', () {
      final result = TypedColumnarResult(
        columns: [
          TypedColumnInt32(
            name: 'id',
            values: Int32List.fromList([1, 2]),
            nullBitmap: Uint8List(1),
          ),
        ],
        rowCount: 2,
      );

      expect(
        mapTypedColumnarToRowMaps(result),
        [
          {'id': 1},
          {'id': 2},
        ],
      );
    });
  });

  group('mapTypedColumnarToChunks', () {
    test('rechunks wide columnar batches by fetchSize', () {
      final result = TypedColumnarResult(
        columns: [
          TypedColumnInt32(
            name: 'id',
            values: Int32List.fromList([1, 2, 3]),
            nullBitmap: Uint8List(1),
          ),
        ],
        rowCount: 3,
      );

      final chunks = mapTypedColumnarToChunks(
        OdbcColumnarStreamChunkMapperInput(result: result, fetchSize: 2),
      );

      expect(chunks.length, 2);
      expect(chunks[0], [
        {'id': 1},
        {'id': 2},
      ]);
      expect(chunks[1], [
        {'id': 3},
      ]);
    });
  });
}
