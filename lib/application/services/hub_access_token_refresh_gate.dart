import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';

/// Shared cooldown and single-flight gate for hub JWT refresh (HTTP renew, coordinator, proactive).
class HubAccessTokenRefreshGate {
  HubAccessTokenRefreshGate({
    Duration minInterval = ConnectionConstants.hubTokenRefreshMinInterval,
  }) : _minInterval = minInterval;

  final Duration _minInterval;
  DateTime? _lastCompletedAt;
  _InflightRefresh? _inFlight;

  bool get isRefreshInFlight => _inFlight != null;

  bool isCooldownActive({DateTime? now}) {
    final minGap = _minInterval;
    final last = _lastCompletedAt;
    if (minGap <= Duration.zero || last == null) {
      return false;
    }
    return (now ?? DateTime.now()).difference(last) < minGap;
  }

  Duration? cooldownRemaining({DateTime? now}) {
    final minGap = _minInterval;
    final last = _lastCompletedAt;
    if (minGap <= Duration.zero || last == null) {
      return null;
    }
    final elapsed = (now ?? DateTime.now()).difference(last);
    if (elapsed >= minGap) {
      return Duration.zero;
    }
    return minGap - elapsed;
  }

  void recordRefreshCompleted({DateTime? at}) {
    _lastCompletedAt = at ?? DateTime.now();
  }

  void reset() {
    _lastCompletedAt = null;
    _inFlight = null;
  }

  /// Runs [action] exclusively. Concurrent callers await the same result.
  ///
  /// Returns null when [respectCooldown] is true, nothing is in flight, and the min
  /// interval has not elapsed since the last successful refresh.
  Future<T?> runExclusive<T>(
    Future<T> Function() action, {
    bool respectCooldown = true,
    String logContext = 'hub_token_refresh',
  }) async {
    final inFlight = _inFlight;
    if (inFlight != null) {
      AppLogger.debug('$logContext event=await_in_flight');
      final shared = await inFlight.completer.future;
      return shared as T?;
    }

    if (respectCooldown && isCooldownActive()) {
      final remaining = cooldownRemaining();
      AppLogger.debug(
        '$logContext event=skipped_min_interval '
        'remaining_ms=${remaining?.inMilliseconds ?? 0}',
      );
      return null;
    }

    final refresh = _InflightRefresh();
    _inFlight = refresh;
    try {
      final result = await action();
      recordRefreshCompleted();
      refresh.completer.complete(result);
      return result;
    } catch (error, stackTrace) {
      refresh.completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      if (identical(_inFlight, refresh)) {
        _inFlight = null;
      }
    }
  }

  /// Waits for an in-flight refresh or the remaining cooldown, whichever applies.
  Future<void> waitForCooldownOrInFlight() async {
    final inFlight = _inFlight;
    if (inFlight != null) {
      try {
        await inFlight.completer.future;
      } on Object {
        // Caller will retry refresh; swallow to unblock waiters.
      }
      return;
    }
    final remaining = cooldownRemaining();
    if (remaining != null && remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }
}

class _InflightRefresh {
  final Completer<Object?> completer = Completer<Object?>();
}
