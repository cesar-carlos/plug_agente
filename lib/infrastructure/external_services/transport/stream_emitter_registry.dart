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

  /// Currently effective cap: `min(negotiated, hardCeiling)`, lower-bounded by
  /// `hardCeiling` whenever the negotiated cap is non-positive (defensive).
  int get effectiveCap {
    final negotiated = _capProvider();
    if (negotiated <= 0) return hardCeiling;
    return negotiated < hardCeiling ? negotiated : hardCeiling;
  }

  bool tryRegister(String streamId, BackpressureStreamEmitter emitter) {
    if (_emitters.containsKey(streamId)) {
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

  void unregister(String streamId) {
    _emitters.remove(streamId);
    _idleTimers.remove(streamId)?.cancel();
  }

  void dispose() {
    for (final timer in _idleTimers.values) {
      timer.cancel();
    }
    _idleTimers.clear();
    _emitters.clear();
  }

  int get activeCount => _emitters.length;

  void _scheduleIdleTimer(String streamId) {
    _idleTimers.remove(streamId)?.cancel();
    _idleTimers[streamId] = Timer(idleTtl, () {
      if (_emitters.remove(streamId) != null) {
        AppLogger.warning(
          'rpc stream emitter evicted by idle TTL '
          '(${idleTtl.inSeconds}s). stream_id=$streamId',
        );
      }
      _idleTimers.remove(streamId);
    });
  }
}
