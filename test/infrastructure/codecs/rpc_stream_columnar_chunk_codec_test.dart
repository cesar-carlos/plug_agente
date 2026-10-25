import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_stream_columnar_chunk_codec.dart';

void main() {
  group('RpcStreamColumnarChunkCodec', () {
    test('preserves numeric SQL nulls and real zeroes in JSON', () {
      final result = TypedColumnarResult(
        rowCount: 3,
        columns: [
          TypedColumnInt32(name: 'i32', values: Int32List.fromList([7, 99, 0]), nullBitmap: Uint8List.fromList([2])),
          TypedColumnInt64(
            name: 'i64',
            values: Int64List.fromList([1234567890123, 99, 0]),
            nullBitmap: Uint8List.fromList([2]),
          ),
          TypedColumnFloat64(
            name: 'f64',
            values: Float64List.fromList([1.25, 99, 0]),
            nullBitmap: Uint8List.fromList([2]),
          ),
        ],
      );
      final encoded = RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result);
      final columns = encoded['columns'] as List<Map<String, dynamic>>;
      expect(columns.map((column) => column['values']).toList(), [
        [7, null, 0],
        [1234567890123, null, 0],
        [1.25, null, 0.0],
      ]);
      expect(jsonEncode(encoded), contains('null'));
      expect((result.columns.first as TypedColumnInt32).values, [7, 99, 0]);
    });

    test('handles null bits across bytes and a short bitmap', () {
      final result = TypedColumnarResult(
        rowCount: 10,
        columns: [
          TypedColumnInt32(name: 'full', values: Int32List(10), nullBitmap: Uint8List.fromList([128, 1])),
          TypedColumnInt32(name: 'short', values: Int32List(10), nullBitmap: Uint8List.fromList([128])),
        ],
      );
      final columns =
          RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result)['columns'] as List<Map<String, dynamic>>;
      expect(columns[0]['values'], [0, 0, 0, 0, 0, 0, 0, null, null, 0]);
      expect(columns[1]['values'], [0, 0, 0, 0, 0, 0, 0, null, 0, 0]);
    });

    test('ignores padding and trailing bitmap bits without copying values', () {
      final values = Int32List.fromList([1, 2]);
      final result = TypedColumnarResult(
        rowCount: 2,
        columns: [
          TypedColumnInt32(name: 'id', values: values, nullBitmap: Uint8List.fromList([252, 255])),
        ],
      );
      final columns =
          RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result)['columns'] as List<Map<String, dynamic>>;
      expect(columns.single['values'], same(values));
    });

    test('encodes typed columnar payload without copying value lists', () {
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

      final encoded = RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result);

      expect(encoded['row_count'], 2);
      final columns = encoded['columns'] as List<Map<String, dynamic>>;
      expect(columns, hasLength(2));
      expect(columns[0]['type'], 'int32');
      expect(columns[0]['values'], same(result.columns[0].values));
      expect(columns[1]['type'], 'object');
      expect(columns[1]['values'], same(result.columns[1].values));
    });
  });
}

extension on TypedColumn {
  List<Object?> get values => switch (this) {
    TypedColumnInt32(:final values) => values,
    TypedColumnInt64(:final values) => values,
    TypedColumnFloat64(:final values) => values,
    TypedColumnObject(:final values) => values,
  };
}
