import 'dart:typed_data';

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

/// Encodes a native columnar ODBC chunk for optional `rpc:chunk` wire payloads.
///
/// Hub consumption is feature-flagged (`ODBC_STREAM_COLUMNAR_WIRE`); legacy hubs
/// continue to receive row-map `rows` only.
final class RpcStreamColumnarChunkCodec {
  RpcStreamColumnarChunkCodec._();

  static Map<String, dynamic> encodeTypedColumnarResult(TypedColumnarResult result) {
    final columns = result.columns;
    final encodedColumns = List<Map<String, dynamic>>.filled(
      columns.length,
      const <String, dynamic>{},
    );
    for (var index = 0; index < columns.length; index++) {
      encodedColumns[index] = _encodeColumn(columns[index]);
    }
    return <String, dynamic>{
      'row_count': result.rowCount,
      'columns': encodedColumns,
    };
  }

  static Map<String, dynamic> _encodeColumn(TypedColumn column) {
    return switch (column) {
      TypedColumnInt32(:final name, :final values, :final nullBitmap) => <String, dynamic>{
        'name': name,
        'type': 'int32',
        'values': _encodeNumericValues(values, nullBitmap),
      },
      TypedColumnInt64(:final name, :final values, :final nullBitmap) => <String, dynamic>{
        'name': name,
        'type': 'int64',
        'values': _encodeNumericValues(values, nullBitmap),
      },
      TypedColumnFloat64(:final name, :final values, :final nullBitmap) => <String, dynamic>{
        'name': name,
        'type': 'float64',
        'values': _encodeNumericValues(values, nullBitmap),
      },
      TypedColumnObject(:final name, :final values) => <String, dynamic>{
        'name': name,
        'type': 'object',
        'values': values,
      },
    };
  }

  static List<T?> _encodeNumericValues<T extends num>(List<T> values, Uint8List bitmap) {
    for (var byte = 0; byte < bitmap.length && byte * 8 < values.length; byte++) {
      final remaining = values.length - byte * 8;
      final mask = remaining >= 8 ? 255 : (1 << remaining) - 1;
      if ((bitmap[byte] & mask) == 0) continue;

      // Typed numeric arrays cannot contain null; allocate only when a SQL
      // null is present, ignoring padding bits outside the value vector.
      return List<T?>.generate(values.length, (row) {
        final index = row >> 3;
        final isNull = index < bitmap.length && (bitmap[index] & (1 << (row & 7))) != 0;
        return isNull ? null : values[row];
      }, growable: false);
    }
    return values;
  }

  static List<Map<String, dynamic>> encodeRowMapsFromColumnar(
    TypedColumnarResult result,
  ) {
    return mapTypedColumnarToRowMaps(result);
  }
}
