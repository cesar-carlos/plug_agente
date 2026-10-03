import 'dart:async';

import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';

/// Bounded registry of active backpressure stream emitters with a passive
/// idle TTL. The TTL fires only when the hub forgets to drive the stream to
/// completion, so eviction usually happens via [unregister]. Eviction logs a
/// warning so leaks are visible in production telemetry.
///
/// The effective cap is the minimum of:
///   - the negotiated `max_concurrent_streams` returned by `capProvider`
///   - [hardCeiling] (absolute defense against a misbehaving hub).
class StreamEmitterRegistry {
  StreamEmitterRegistry({
    required this.hardCeiling,
    required this.idleTtl,
    int Function()? capProvider,
  }) : _capProvider = capProvider ?? (() => hardCeiling);

  final int hardCeiling;
  final Duration idleTtl;
  final int Function() _capProvider;
  final Map<String, BackpressureStreamEmitter> _emitters = {};
  final Map<String, Timer> _idleTimers = {};
  int expiredEmitters = 0;
  int _queuePeak = 0;
  int get activeTimers => _idleTimers.length;

  // Internal diagnostics are sampled outside the frame path and never added
  // to agent.getHealth or other public protocol snapshots.
  Map<String, int> get diagnostics => {
    'active_emitters': activeCount,
    'active_timers': activeTimers,
    'expired_emitters': expiredEmitters,
    'queued_chunks': _emitters.values.fold(0, (sum, emitter) => sum + emitter.queuedChunks),
    'queue_peak': _emitters.values.fold(
      _queuePeak,
      (peak, emitter) => emitter.queuedChunksPeak > peak ? emitter.queuedChunksPeak : peak,
    ),
  };

  void _recordPeak(BackpressureStreamEmitter emitter) {
    if (emitter.queuedChunksPeak > _queuePeak) _queuePeak = emitter.queuedChunksPeak;
  }

  /// Currently effective cap: `min(negotiated, hardCeiling)`, lower-bounded by
  /// `hardCeiling` whenever the negotiated cap is non-positive (defensive).
  int get effectiveCap {
    final negotiated = _capProvider();
    if (negotiated <= 0) return hardCeiling;
    return negotiated < hardCeiling ? negotiated : hardCeiling;
  }

  bool tryRegister(String streamId, BackpressureStreamEmitter emitter) {
    if (_emitters.containsKey(streamId)) {
      final previous = _emitters[streamId]!;
      if (!identical(previous, emitter)) {
        _recordPeak(previous);
        previous.onTransportLoss();
      }
      _emitters[streamId] = emitter;
      _scheduleIdleTimer(streamId);
      return true;
    }
    if (_emitters.length >= effectiveCap) {
      return false;
    }
    _emitters[streamId] = emitter;
    _scheduleIdleTimer(streamId);
    return true;
  }

  BackpressureStreamEmitter? get(String streamId) => _emitters[streamId];

  void touch(String streamId) {
    if (_emitters.containsKey(streamId)) {
      _scheduleIdleTimer(streamId);
    }
  }

  void unregister(String streamId, {BackpressureStreamEmitter? emitter}) {
    if (emitter != null && !identical(_emitters[streamId], emitter)) return;
    final removed = _emitters.remove(streamId);
    if (removed != null) _recordPeak(removed);
    _idleTimers.remove(streamId)?.cancel();
  }

  void dispose() {
    for (final timer in _idleTimers.values) {
      timer.cancel();
    }
    _idleTimers.clear();
    // Fault producers before clearing so they are not left with
    // `_registered == true` after soft reconnect frees the slots.
    final emitters = List<BackpressureStreamEmitter>.of(_emitters.values);
    for (final emitter in emitters) {
      _recordPeak(emitter);
      emitter.onTransportLoss();
    }
    _emitters.clear();
  }

  int get activeCount => _emitters.length;

  void _scheduleIdleTimer(String streamId) {
    _idleTimers.remove(streamId)?.cancel();
    final emitter = _emitters[streamId];
    _idleTimers[streamId] = Timer(idleTtl, () {
      if (emitter != null && identical(_emitters[streamId], emitter)) {
        _recordPeak(emitter);
        emitter.onTransportLoss();
        _emitters.remove(streamId);
        expiredEmitters++;
        AppLogger.warning(
          'rpc stream emitter evicted by idle TTL '
          '(${idleTtl.inSeconds}s). stream_id=$streamId',
        );
        _idleTimers.remove(streamId);
      }
    });
  }
}
