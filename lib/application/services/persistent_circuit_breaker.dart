import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Snapshot returned by [PersistentCircuitBreaker.recordFailure] so the
/// caller can mirror the failure count and cooldown deadline into
/// diagnostics fields, without re-reading the settings store.
class PersistentCircuitBreakerState {
  const PersistentCircuitBreakerState({required this.failureCount, this.cooldownUntil});
  final int failureCount;
  final DateTime? cooldownUntil;
}

/// Generic "N consecutive failures → cooldown window" gate persisted on
/// disk via [IAppSettingsStore]. Deduplicates the two cooldowns the
/// auto-update flow needs:
///
/// - **manual check timeout circuit** (in the orchestrator);
/// - **automatic silent failure cooldown** (in the coordinator).
///
/// Each instance owns two settings keys (`countKey`, `cooldownKey`).
/// Pass distinct names for distinct breakers — the breaker does not own
/// the namespace.
class PersistentCircuitBreaker {
  PersistentCircuitBreaker({
    required this.countKey,
    required this.cooldownKey,
    required this.threshold,
    required this.cooldown,
    required this.logName,
    IAppSettingsStore? settingsStore,
    DateTime Function()? clock,
  }) : _settingsStore = settingsStore,
       _clock = clock ?? DateTime.now;

  final String countKey;
  final String cooldownKey;
  final int threshold;
  final Duration cooldown;
  final String logName;
  final IAppSettingsStore? _settingsStore;
  final DateTime Function() _clock;

  int get failureCount => _settingsStore?.getInt(countKey) ?? 0;

  DateTime? get cooldownUntil {
    final timestamp = _settingsStore?.getInt(cooldownKey);
    if (timestamp == null || timestamp <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  /// Returns the remaining cooldown when the breaker is open, `null`
  /// when it is closed (no cooldown active). Resets the persisted state
  /// when the cooldown window has elapsed so the next caller no longer
  /// sees the breaker as open.
  Future<Duration?> remainingCooldown() async {
    final until = cooldownUntil;
    if (until == null) return null;
    final remaining = until.difference(_clock());
    if (remaining.isNegative || remaining == Duration.zero) {
      await reset();
      return null;
    }
    return remaining;
  }

  /// Increments the failure counter and, when it crosses [threshold],
  /// computes a new cooldown deadline. Returns both values so the caller
  /// can mirror them into diagnostics in a single round-trip.
  Future<PersistentCircuitBreakerState> recordFailure() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) {
      return const PersistentCircuitBreakerState(failureCount: 0);
    }
    final nextCount = failureCount + 1;
    DateTime? newCooldownUntil;
    final values = <String, Object>{countKey: nextCount};
    if (nextCount >= threshold) {
      newCooldownUntil = _clock().add(cooldown);
      values[cooldownKey] = newCooldownUntil.millisecondsSinceEpoch;
    }
    try {
      await settingsStore.setValues(values);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist $logName cooldown state',
        name: logName,
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return PersistentCircuitBreakerState(
      failureCount: nextCount,
      cooldownUntil: newCooldownUntil,
    );
  }

  /// Clears the breaker. No-op when neither key is present so the common
  /// "no failures yet" path stays a single map lookup.
  Future<void> reset() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) return;
    final hasCount = settingsStore.containsKey(countKey);
    final hasCooldown = settingsStore.containsKey(cooldownKey);
    if (!hasCount && !hasCooldown) return;
    try {
      await settingsStore.remove(countKey);
      await settingsStore.remove(cooldownKey);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to reset $logName cooldown state',
        name: logName,
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
