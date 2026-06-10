import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';

/// Snapshot returned by [PersistentCircuitBreaker.recordFailure] so the
/// caller can mirror the failure count and cooldown deadline into
/// diagnostics fields, without re-reading the settings store.
class PersistentCircuitBreakerState {
  const PersistentCircuitBreakerState({required this.failureCount, this.cooldownUntil});
  final int failureCount;
  final DateTime? cooldownUntil;
}

/// Generic "N consecutive failures → cooldown window" gate persisted via
/// [ICircuitBreakerPersistence]. Deduplicates the two cooldowns the
/// auto-update flow needs:
///
/// - **manual check timeout circuit** (in the orchestrator);
/// - **automatic silent failure cooldown** (in the coordinator).
class PersistentCircuitBreaker {
  PersistentCircuitBreaker({
    required ICircuitBreakerPersistence persistence,
    required this.threshold,
    required this.cooldown,
    required this.logName,
    DateTime Function()? clock,
  }) : _persistence = persistence,
       _clock = clock ?? DateTime.now;

  final ICircuitBreakerPersistence _persistence;
  final int threshold;
  final Duration cooldown;
  final String logName;
  final DateTime Function() _clock;

  int get failureCount => _persistence.failureCount;

  DateTime? get cooldownUntil => _persistence.cooldownUntil;

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
    final nextCount = failureCount + 1;
    DateTime? newCooldownUntil;
    if (nextCount >= threshold) {
      newCooldownUntil = _clock().add(cooldown);
    }
    try {
      await _persistence.persistFailure(
        failureCount: nextCount,
        cooldownUntil: newCooldownUntil,
      );
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
    try {
      await _persistence.clear();
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
