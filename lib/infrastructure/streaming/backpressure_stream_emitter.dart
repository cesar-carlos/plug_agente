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
    required Future<bool> Function(String event, Map<String, dynamic> payload) emit,
    required bool Function(String streamId, BackpressureStreamEmitter emitter) onRegister,
    required void Function(String streamId) onUnregister,
    int? maxQueueSize,
    int? initialSendCredit,
  }) : _emit = emit,
       _onRegister = onRegister,
       _onUnregister = onUnregister,
       _maxQueueSize = maxQueueSize ?? ConnectionConstants.maxBackpressureChunkQueueSize,
       _sendCredit = initialSendCredit ?? 1;

  final Future<bool> Function(String event, Map<String, dynamic> payload) _emit;
  final bool Function(String streamId, BackpressureStreamEmitter emitter) _onRegister;
  final void Function(String streamId) _onUnregister;
  final int _maxQueueSize;

  final Queue<RpcStreamChunk> _chunkQueue = Queue<RpcStreamChunk>();
  RpcStreamComplete? _pendingComplete;
  String? _streamId;
  bool _registered = false;
  // Once a flush fails (e.g., socket emit threw), the emitter is poisoned: we
  // do not try to drain further chunks because the underlying transport is
  // unreliable. Future [emitChunk] calls return `false` so the caller falls
  // back to its overflow handling (typically cancelling the active stream).
  bool _isFaulted = false;
  bool _completed = false;
  bool _completionRequested = false;
  int _sendCredit;

  // One drain observes arrivals and new credit across its awaits. Callers do
  // not allocate a continuation chain for every request to resume flushing.
  Future<void>? _flushInFlight;
  int _queuedPeak = 0;
  int get queuedChunks => _chunkQueue.length;
  int get queuedChunksPeak => _queuedPeak;
  int get availableCredit => _sendCredit;

  /// Whether the emitter has stopped trying to deliver chunks because a
  /// previous emit threw. Exposed for diagnostics and tests.
  bool get isFaulted => _isFaulted;

  /// Marks this emitter dead after soft transport loss so producers stop
  /// flushing and do not believe they are still registered.
  ///
  /// Does not call onUnregister: the registry owns map cleanup on dispose.
  void onTransportLoss() {
    _isFaulted = true;
    _chunkQueue.clear();
    _pendingComplete = null;
    _registered = false;
  }

  void releaseChunks(int windowSize) {
    if (windowSize <= 0 || _isFaulted || _completed) return;
    _sendCredit += windowSize;
    _scheduleFlush();
  }

  Future<void> _scheduleFlush() {
    if (_flushInFlight case final pending?) return pending;
    final gate = Completer<void>();
    _flushInFlight = gate.future;
    // Admission is synchronous; one drain observes arrivals during its await.
    scheduleMicrotask(() async {
      try {
        await _flushBody();
      } on Object catch (error, stack) {
        await _handleFlushError(error, stack);
      } finally {
        _flushInFlight = null;
        gate.complete();
        if (!_isFaulted &&
            !_completed &&
            ((_sendCredit > 0 && _chunkQueue.isNotEmpty) || (_pendingComplete != null && _chunkQueue.isEmpty))) {
          unawaited(_scheduleFlush());
        }
      }
    });
    return gate.future;
  }

  Future<void> _handleFlushError(Object error, StackTrace stackTrace) async {
    _isFaulted = true;
    _chunkQueue.clear();
    _pendingComplete = null;
    final streamId = _streamId;
    if (streamId != null && _registered) {
      _registered = false;
      _onUnregister(streamId);
    }
    AppLogger.error(
      'BackpressureStreamEmitter faulted; resetting flush chain. '
      'stream_id=${streamId ?? '<unknown>'}',
      error,
      stackTrace,
    );
  }

  Future<void> _flushBody() async {
    if (_isFaulted) return;
    while (!_isFaulted && !_completed && _sendCredit > 0 && _chunkQueue.isNotEmpty) {
      final chunk = _chunkQueue.removeFirst();
      _sendCredit--;
      final payload = chunk.toJson();
      final emitted = await _emit('rpc:chunk', payload);
      if (!emitted) {
        throw StateError('rpc stream chunk emit returned false');
      }
      if (_isFaulted) return;
    }
    await _maybeEmitComplete();
  }

  Future<void> _maybeEmitComplete() async {
    if (_pendingComplete == null || _chunkQueue.isNotEmpty || _isFaulted) {
      return;
    }
    final complete = _pendingComplete!;
    _pendingComplete = null;
    _completed = true;
    final payload = complete.toJson();
    try {
      final emitted = await _emit('rpc:complete', payload);
      if (!emitted) {
        throw StateError('rpc stream complete emit returned false');
      }
    } finally {
      // Always free the registry slot. Negotiated max_concurrent_streams can
      // be 1 (hub advertisement); a leaked emitter blocks the next streaming
      // RPC until idle TTL (300s) — matching Colmeia E2E tag timeouts.
      if (_streamId != null && _registered) {
        _registered = false;
        _onUnregister(_streamId!);
      }
    }
  }

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    if (_isFaulted || _completionRequested || _completed) {
      return false;
    }
    if (!_registered) {
      _streamId = chunk.streamId;
      final accepted = _onRegister(_streamId!, this);
      if (!accepted) {
        return false;
      }
      _registered = true;
    }

    if (_chunkQueue.length >= _maxQueueSize) return false;
    _chunkQueue.add(chunk);
    if (_chunkQueue.length > _queuedPeak) _queuedPeak = _chunkQueue.length;
    await _scheduleFlush();
    return !_isFaulted;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {
    if (_isFaulted || _completionRequested || _completed) {
      return;
    }
    _completionRequested = true;
    _pendingComplete = complete;
    await _scheduleFlush();
  }
}
