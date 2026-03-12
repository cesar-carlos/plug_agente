import 'package:plug_agente/domain/protocol/rpc_stream.dart';

/// Emitter for RPC streaming events (rpc:chunk, rpc:complete).
///
/// Used when `enableSocketStreamingChunks` is active. The dispatcher calls
/// [emitChunk] for each chunk and [emitComplete] when done.
abstract class IRpcStreamEmitter {
  void emitChunk(RpcStreamChunk chunk);
  void emitComplete(RpcStreamComplete complete);
}
