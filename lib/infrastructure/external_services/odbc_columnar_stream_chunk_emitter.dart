import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_stream_columnar_chunk_codec.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_chunk_mapper.dart';

/// Emits native columnar ODBC chunks to Hub row maps and/or wire columnar payloads.
final class OdbcColumnarStreamChunkEmitter {
  const OdbcColumnarStreamChunkEmitter._();

  static Future<void> emit({
    required TypedColumnarResult result,
    required int fetchSize,
    required Future<void> Function(List<Map<String, dynamic>> chunk) onChunk,
    Future<void> Function(StreamingWireChunk chunk)? onWireChunk,
    bool includeColumnarWire = false,
    bool wireOnly = false,
    bool Function()? isCancelRequested,
  }) async {
    if (isCancelRequested?.call() ?? false) {
      return;
    }
    if (onWireChunk != null && includeColumnarWire) {
      await onWireChunk(
        StreamingWireChunk(
          rows: const <Map<String, dynamic>>[],
          columnar: RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result),
        ),
      );
      return;
    }

    final batchSize = effectiveStreamingFetchSize(fetchSize);
    for (var start = 0; start < result.rowCount; start += batchSize) {
      final remaining = result.rowCount - start;
      final length = remaining < batchSize ? remaining : batchSize;
      final chunk = List<Map<String, dynamic>>.generate(
        length,
        (index) => mapTypedColumnarRow(result.columns, start + index),
        growable: result.rowCount > batchSize,
      );
      await onChunk(chunk);
      if (result.rowCount > batchSize) {
        await Future<void>.delayed(Duration.zero);
      }
      if (isCancelRequested?.call() ?? false) {
        return;
      }
    }
  }
}
