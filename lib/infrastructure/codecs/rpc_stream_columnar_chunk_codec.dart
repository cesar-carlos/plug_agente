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
      TypedColumnInt32(:final name, :final values) => <String, dynamic>{
        'name': name,
        'type': 'int32',
        'values': values,
      },
      TypedColumnInt64(:final name, :final values) => <String, dynamic>{
        'name': name,
        'type': 'int64',
        'values': values,
      },
      TypedColumnFloat64(:final name, :final values) => <String, dynamic>{
        'name': name,
        'type': 'float64',
        'values': values,
      },
      TypedColumnObject(:final name, :final values) => <String, dynamic>{
        'name': name,
        'type': 'object',
        'values': values,
      },
    };
  }

  static List<Map<String, dynamic>> encodeRowMapsFromColumnar(
    TypedColumnarResult result,
  ) {
    return mapTypedColumnarToRowMaps(result);
  }
}
