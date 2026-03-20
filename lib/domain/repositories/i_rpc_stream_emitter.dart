import 'package:plug_agente/domain/protocol/rpc_stream.dart';

/// Emitter for RPC streaming events (rpc:chunk, rpc:complete).
///
/// Used when `enableSocketStreamingChunks` is active. The dispatcher calls
/// [emitChunk] for each chunk and [emitComplete] when done.
///
/// [emitChunk] returns `true` if the chunk was accepted, `false` if the buffer
/// overflowed (e.g. hub not consuming fast enough). Callers must stop producing
/// and return an explicit error instead of silently dropping data.
abstract class IRpcStreamEmitter {
  /// Returns `true` if accepted, `false` on buffer overflow.
  bool emitChunk(RpcStreamChunk chunk);
  void emitComplete(RpcStreamComplete complete);
}
