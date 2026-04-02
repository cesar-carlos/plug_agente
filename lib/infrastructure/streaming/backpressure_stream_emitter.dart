import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';

/// Stream emitter that applies backpressure: enqueues chunks and sends only
/// when credit is available. Initial credit is 1; [releaseChunks] adds more.
class BackpressureStreamEmitter implements IRpcStreamEmitter {
  BackpressureStreamEmitter({
    required Future<void> Function(String event, Map<String, dynamic> payload) emit,
    required void Function(String streamId, BackpressureStreamEmitter emitter) onRegister,
    required void Function(String streamId) onUnregister,
    int? maxQueueSize,
  }) : _emit = emit,
       _onRegister = onRegister,
       _onUnregister = onUnregister,
       _maxQueueSize = maxQueueSize ?? ConnectionConstants.maxBackpressureChunkQueueSize;

  final Future<void> Function(String event, Map<String, dynamic> payload) _emit;
  final void Function(String streamId, BackpressureStreamEmitter emitter) _onRegister;
  final void Function(String streamId) _onUnregister;
  final int _maxQueueSize;

  final Queue<RpcStreamChunk> _chunkQueue = Queue<RpcStreamChunk>();
  RpcStreamComplete? _pendingComplete;
  String? _streamId;
  bool _registered = false;
  int _sendCredit = 1;

  void releaseChunks(int windowSize) {
    if (windowSize <= 0) return;
    _sendCredit += windowSize;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    while (_sendCredit > 0 && _chunkQueue.isNotEmpty) {
      final chunk = _chunkQueue.removeFirst();
      final payload = chunk.toJson();
      await _emit('rpc:chunk', payload);
      _sendCredit--;
    }
    await _maybeEmitComplete();
  }

  Future<void> _maybeEmitComplete() async {
    if (_pendingComplete == null || _chunkQueue.isNotEmpty) return;
    final complete = _pendingComplete!;
    _pendingComplete = null;
    final payload = complete.toJson();
    await _emit('rpc:complete', payload);
    if (_streamId != null) {
      _onUnregister(_streamId!);
    }
  }

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    if (!_registered) {
      _streamId = chunk.streamId;
      _onRegister(_streamId!, this);
      _registered = true;
    }
    await _flush();
    if (_chunkQueue.length >= _maxQueueSize && _sendCredit == 0) {
      return false;
    }
    _chunkQueue.add(chunk);
    await _flush();
    return true;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {
    _pendingComplete = complete;
    await _maybeEmitComplete();
  }
}
