import 'package:plug_agente/domain/protocol/rpc_stream.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

/// Captures [RpcStreamChunk] / [RpcStreamComplete] for live RPC streaming E2E.
final class OdbcE2eRecordingRpcStreamEmitter implements IRpcStreamEmitter {
  final List<RpcStreamChunk> chunks = <RpcStreamChunk>[];

  RpcStreamComplete? complete;

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    chunks.add(chunk);
    return true;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete value) async {
    complete = value;
  }
}
