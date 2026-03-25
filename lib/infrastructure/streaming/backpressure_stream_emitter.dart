import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
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

  final ListQueue<RpcStreamChunk> _chunkQueue = ListQueue<RpcStreamChunk>();
  RpcStreamComplete? _pendingComplete;
  String? _streamId;
  bool _registered = false;
  int _sendCredit = 1;
  bool _cancelled = false;

  /// Drops queued work and unregisters from the transport map (e.g. on disconnect).
  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _chunkQueue.clear();
    _pendingComplete = null;
    if (_registered && _streamId != null) {
      _onUnregister(_streamId!);
      _registered = false;
    }
  }

  void releaseChunks(int windowSize) {
    if (_cancelled || windowSize <= 0) return;
    _sendCredit += windowSize;
    unawaited(
      _flush().catchError((Object error, StackTrace stackTrace) {
        AppLogger.error(
          'BackpressureStreamEmitter flush failed',
          error,
          stackTrace,
        );
      }),
    );
  }

  Future<void> _flush() async {
    if (_cancelled) {
      return;
    }
    while (_sendCredit > 0 && _chunkQueue.isNotEmpty) {
      final chunk = _chunkQueue.removeFirst();
      final payload = chunk.toJson();
      // Consume credit before awaiting emit so concurrent _flush() calls cannot
      // dequeue extra chunks while this send is still in flight.
      _sendCredit--;
      try {
        await _emit('rpc:chunk', payload);
      } on Object catch (error, stackTrace) {
        _sendCredit++;
        _chunkQueue.addFirst(chunk);
        AppLogger.error(
          'rpc:chunk emit failed; chunk re-queued',
          error,
          stackTrace,
        );
        rethrow;
      }
    }
    await _maybeEmitComplete();
  }

  Future<void> _maybeEmitComplete() async {
    if (_pendingComplete == null || _chunkQueue.isNotEmpty) return;
    final complete = _pendingComplete!;
    _pendingComplete = null;
    final payload = complete.toJson();
    try {
      await _emit('rpc:complete', payload);
    } on Object catch (error, stackTrace) {
      AppLogger.error(
        'rpc:complete emit failed',
        error,
        stackTrace,
      );
      rethrow;
    } finally {
      if (_streamId != null) {
        _onUnregister(_streamId!);
      }
    }
  }

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    if (_cancelled) {
      return false;
    }
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
    if (_cancelled) {
      return;
    }
    _pendingComplete = complete;
    await _maybeEmitComplete();
  }
}
