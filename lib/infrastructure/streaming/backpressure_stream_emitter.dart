import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

/// Stream emitter that applies backpressure: enqueues chunks and sends only
/// when credit is available. Initial credit is 1; [releaseChunks] adds more.
class BackpressureStreamEmitter implements IRpcStreamEmitter {
  BackpressureStreamEmitter({
    required void Function(String event, Map<String, dynamic> payload) emit,
    required void Function(String streamId, BackpressureStreamEmitter emitter)
    onRegister,
    required void Function(String streamId) onUnregister,
  }) : _emit = emit,
       _onRegister = onRegister,
       _onUnregister = onUnregister;

  final void Function(String event, Map<String, dynamic> payload) _emit;
  final void Function(String streamId, BackpressureStreamEmitter emitter)
  _onRegister;
  final void Function(String streamId) _onUnregister;

  final List<RpcStreamChunk> _chunkQueue = [];
  RpcStreamComplete? _pendingComplete;
  String? _streamId;
  bool _registered = false;
  int _sendCredit = 1;

  void releaseChunks(int windowSize) {
    if (windowSize <= 0) return;
    _sendCredit += windowSize;
    _flush();
  }

  void _flush() {
    while (_sendCredit > 0 && _chunkQueue.isNotEmpty) {
      final chunk = _chunkQueue.removeAt(0);
      final payload = chunk.toJson();
      _emit('rpc:chunk', payload);
      _sendCredit--;
    }
    _maybeEmitComplete();
  }

  void _maybeEmitComplete() {
    if (_pendingComplete == null || _chunkQueue.isNotEmpty) return;
    final complete = _pendingComplete!;
    _pendingComplete = null;
    final payload = complete.toJson();
    _emit('rpc:complete', payload);
    if (_streamId != null) {
      _onUnregister(_streamId!);
    }
  }

  @override
  void emitChunk(RpcStreamChunk chunk) {
    if (!_registered) {
      _streamId = chunk.streamId;
      _onRegister(_streamId!, this);
      _registered = true;
    }
    _chunkQueue.add(chunk);
    while (_chunkQueue.length >
        ConnectionConstants.maxBackpressureChunkQueueSize) {
      _chunkQueue.removeAt(0);
    }
    _flush();
  }

  @override
  void emitComplete(RpcStreamComplete complete) {
    _pendingComplete = complete;
    _maybeEmitComplete();
  }
}
