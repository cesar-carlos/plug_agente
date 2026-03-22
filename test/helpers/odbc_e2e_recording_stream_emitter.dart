import 'package:plug_agente/domain/protocol/rpc_stream.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

/// Captures [RpcStreamChunk] / [RpcStreamComplete] for live RPC streaming E2E.
final class OdbcE2eRecordingRpcStreamEmitter implements IRpcStreamEmitter {
  OdbcE2eRecordingRpcStreamEmitter() : _stopwatch = Stopwatch()..start();

  final List<RpcStreamChunk> chunks = <RpcStreamChunk>[];
  final Stopwatch _stopwatch;

  RpcStreamComplete? complete;
  int? firstChunkLatencyMs;
  int? completeLatencyMs;

  int get chunkCount => chunks.length;

  int get totalChunkRows =>
      chunks.fold<int>(0, (int total, RpcStreamChunk chunk) {
        return total + chunk.rows.length;
      });

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    firstChunkLatencyMs ??= _stopwatch.elapsedMilliseconds;
    chunks.add(chunk);
    return true;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete value) async {
    complete = value;
    completeLatencyMs = _stopwatch.elapsedMilliseconds;
  }
}
