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
  int _sendCredit;

  // Serializes _flush calls so concurrent releaseChunks + emitChunk invocations
  // cannot reorder chunk_index on the wire. Each caller chains onto the
  // previous in-flight future; only one flush body runs at a time.
  Future<void> _flushInFlight = Future<void>.value();

  // Serializes queue admission (overflow check + enqueue) without waiting for
  // the full wire flush, so producers can pipeline chunk submission.
  Future<void> _admissionChain = Future<void>.value();

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
    if (windowSize <= 0 || _isFaulted) return;
    _sendCredit += windowSize;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    // Chain through `.then(...)` so flushes serialize; recover via
    // `.catchError(...)` so a single failure does not poison every future
    // continuation. We still mark the emitter as faulted inside _flushBody so
    // new emitChunk/releaseChunks calls short-circuit at the public surface.
    _flushInFlight = _flushInFlight.then((_) => _flushBody()).catchError(_handleFlushError);
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
    while (_sendCredit > 0 && _chunkQueue.isNotEmpty) {
      final chunk = _chunkQueue.removeFirst();
      final payload = chunk.toJson();
      final emitted = await _emit('rpc:chunk', payload);
      if (!emitted) {
        throw StateError('rpc stream chunk emit returned false');
      }
      _sendCredit--;
    }
    await _maybeEmitComplete();
  }

  Future<void> _maybeEmitComplete() async {
    if (_pendingComplete == null || _chunkQueue.isNotEmpty || _isFaulted) {
      return;
    }
    final complete = _pendingComplete!;
    _pendingComplete = null;
    final payload = complete.toJson();
    final emitted = await _emit('rpc:complete', payload);
    if (!emitted) {
      throw StateError('rpc stream complete emit returned false');
    }
    if (_streamId != null) {
      _onUnregister(_streamId!);
    }
  }

  @override
  Future<bool> emitChunk(RpcStreamChunk chunk) async {
    if (_isFaulted) {
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

    final previousAdmission = _admissionChain;
    final admissionGate = Completer<void>();
    _admissionChain = admissionGate.future;
    await previousAdmission;

    try {
      if (_isFaulted) {
        return false;
      }
      if (_chunkQueue.length >= _maxQueueSize && _sendCredit == 0) {
        return false;
      }
      _chunkQueue.add(chunk);
      _scheduleFlush();
    } finally {
      admissionGate.complete();
    }

    await _flushInFlight;
    return !_isFaulted;
  }

  @override
  Future<void> emitComplete(RpcStreamComplete complete) async {
    if (_isFaulted) {
      return;
    }
    _pendingComplete = complete;
    _scheduleFlush();
    await _flushInFlight;
  }
}
