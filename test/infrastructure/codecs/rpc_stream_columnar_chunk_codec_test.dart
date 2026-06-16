import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_stream_columnar_chunk_codec.dart';

void main() {
  group('RpcStreamColumnarChunkCodec', () {
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
