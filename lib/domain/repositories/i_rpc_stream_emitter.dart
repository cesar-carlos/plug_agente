import 'package:plug_agente/domain/protocol/rpc_stream.dart';

/// Emitter for RPC streaming events (rpc:chunk, rpc:complete).
///
/// Used when `enableSocketStreamingChunks` is active. The dispatcher calls
/// [emitChunk] for each chunk and [emitComplete] when done.
///
/// [emitChunk] returns `true` if the chunk was accepted, `false` if the buffer
/// overflowed (e.g. hub not consuming fast enough). Callers must stop producing
/// and return an explicit error instead of silently dropping data.
///
/// Methods are asynchronous so framing (JSON + optional gzip) can run
/// off the UI thread without blocking it.
abstract class IRpcStreamEmitter {
  /// Returns `true` if accepted, `false` on buffer overflow.
  Future<bool> emitChunk(RpcStreamChunk chunk);
  Future<void> emitComplete(RpcStreamComplete complete);
}
