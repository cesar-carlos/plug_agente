import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/streaming/streaming_wire_chunk.dart';
import 'package:plug_agente/infrastructure/codecs/rpc_stream_columnar_chunk_codec.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_columnar_stream_chunk_mapper.dart';

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
    final columnarPayload = includeColumnarWire ? RpcStreamColumnarChunkCodec.encodeTypedColumnarResult(result) : null;

    if (onWireChunk != null && columnarPayload != null) {
      await onWireChunk(
        StreamingWireChunk(
          rows: const <Map<String, dynamic>>[],
          columnar: columnarPayload,
        ),
      );
      return;
    }

    final chunks = mapTypedColumnarToChunks(
      OdbcColumnarStreamChunkMapperInput(
        result: result,
        fetchSize: fetchSize,
      ),
    );

    for (final chunk in chunks) {
      await onChunk(chunk);
      if (chunks.length > 1) {
        await Future<void>.delayed(Duration.zero);
      }
      if (isCancelRequested?.call() ?? false) {
        return;
      }
    }
  }
}
