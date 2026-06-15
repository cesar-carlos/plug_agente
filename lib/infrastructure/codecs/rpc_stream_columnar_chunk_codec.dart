import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

/// Encodes a native columnar ODBC chunk for optional `rpc:chunk` wire payloads.
///
/// Hub consumption is feature-flagged (`ODBC_STREAM_COLUMNAR_WIRE`); legacy hubs
/// continue to receive row-map `rows` only.
final class RpcStreamColumnarChunkCodec {
  RpcStreamColumnarChunkCodec._();

  static Map<String, dynamic> encodeTypedColumnarResult(TypedColumnarResult result) {
    final columns = result.columns.map(_encodeColumn).toList(growable: false);
    return <String, dynamic>{
      'row_count': result.rowCount,
      'columns': columns,
    };
  }

  static Map<String, dynamic> _encodeColumn(TypedColumn column) {
    final payload = <String, dynamic>{'name': column.name};
    switch (column) {
      case TypedColumnInt32(:final values):
        payload['type'] = 'int32';
        payload['values'] = values;
      case TypedColumnInt64(:final values):
        payload['type'] = 'int64';
        payload['values'] = values;
      case TypedColumnFloat64(:final values):
        payload['type'] = 'float64';
        payload['values'] = values;
      case TypedColumnObject(:final values):
        payload['type'] = 'object';
        payload['values'] = values;
    }
    return payload;
  }

  static List<Map<String, dynamic>> encodeRowMapsFromColumnar(
    TypedColumnarResult result,
  ) {
    return mapTypedColumnarToRowMaps(result);
  }
}
