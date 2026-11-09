import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/utils/odbc_wire_cell_normalizer.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

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
    test('matches package materialization for mixed nullable columns across bitmap boundaries', () {
      final lazy = LazyString(Uint8List.fromList(utf8.encode('ação 😀')));
      final binary = Uint8List.fromList([0, 127, 255]);
      final largeInteger = int.parse('9007199254740993');
      final result = TypedColumnarResult(
        columns: [
          TypedColumnInt32(
            name: 'id',
            values: Int32List.fromList(List.generate(10, (i) => i)),
            nullBitmap: Uint8List.fromList([0x80, 0x01]),
          ),
          TypedColumnInt64(
            name: 'large',
            values: Int64List.fromList(List.filled(10, largeInteger)),
            nullBitmap: Uint8List.fromList([0x80, 0x01]),
          ),
          TypedColumnFloat64(
            name: 'score',
            values: Float64List.fromList(List.filled(10, -1.25)),
            nullBitmap: Uint8List.fromList([0x80, 0x01]),
          ),
          TypedColumnObject<Object>(
            name: 'text',
            kind: TypedColumnKind.string,
            values: List.generate(10, (i) => i == 8 ? null : lazy),
          ),
          TypedColumnObject<Object>(
            name: 'binary',
            kind: TypedColumnKind.bytes,
            values: List.generate(10, (i) => i == 8 ? null : binary),
          ),
          TypedColumnObject<Object>(
            name: 'date',
            kind: TypedColumnKind.dateTime,
            values: List.generate(10, (i) => i == 8 ? null : '2026-11-09 12:00:00'),
          ),
        ],
        rowCount: 10,
      );

      final materialized = fromTypedColumnar(result);
      final expected = mapQueryResultRows(materialized.columns, materialized.rows);
      final actual = mapTypedColumnarToRowMaps(
        result,
      ).map((row) => row.map((key, value) => MapEntry(key, normalizeOdbcWireCell(value)))).toList();

      expect(actual, expected);
      expect(actual[0]['large'], largeInteger);
      expect(actual[0]['text'], 'ação 😀');
      expect(actual[0]['binary'], 'AH//');
      expect(actual[7]['id'], isNull);
      expect(actual[8].values, everyElement(isNull));
      expect(actual[9]['id'], 9);
      materialized.rows[0][0] = -1;
      expect(readTypedColumnarCell(result.columns.first, 0), 0);
      expect(materialized.rows[1][0], 1);
    });

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
