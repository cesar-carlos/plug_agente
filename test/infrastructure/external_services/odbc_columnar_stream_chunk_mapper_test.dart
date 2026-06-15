import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

void main() {
  group('readTypedColumnarCell', () {
    test('passes string date values through for dateTime columns', () {
      final column = TypedColumnObject<Object>(
        name: 'data_cadastro',
        kind: TypedColumnKind.dateTime,
        values: <Object?>['2024-06-15 12:00:00', null],
      );

      expect(readTypedColumnarCell(column, 0), '2024-06-15 12:00:00');
      expect(readTypedColumnarCell(column, 1), isNull);
    });

    test('keeps DateTime values for dateTime columns', () {
      final value = DateTime.utc(2024, 6, 15, 12);
      final column = TypedColumnObject<DateTime>(
        name: 'data_cadastro',
        kind: TypedColumnKind.dateTime,
        values: <DateTime?>[value],
      );

      expect(readTypedColumnarCell(column, 0), value);
    });
  });

  group('mapTypedColumnarToRowMaps', () {
    test('maps string dateTime column to row maps', () {
      final result = TypedColumnarResult(
        columns: [
          TypedColumnObject<Object>(
            name: 'data_cadastro',
            kind: TypedColumnKind.dateTime,
            values: <Object?>['2024-06-15 12:00:00'],
          ),
        ],
        rowCount: 1,
      );

      expect(
        mapTypedColumnarToRowMaps(result),
        [
          {'data_cadastro': '2024-06-15 12:00:00'},
        ],
      );
    });

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
