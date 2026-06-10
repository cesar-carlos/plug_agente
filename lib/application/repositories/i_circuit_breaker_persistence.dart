import 'package:plug_agente/application/services/persistent_circuit_breaker.dart' show PersistentCircuitBreaker;

/// Persistence port for [PersistentCircuitBreaker] state scoped to update prefs.
abstract interface class ICircuitBreakerPersistence {
  int get failureCount;

  DateTime? get cooldownUntil;

  Future<void> persistFailure({
    required int failureCount,
    DateTime? cooldownUntil,
  });

  Future<void> clear();
}

/// In-memory persistence for tests and degraded runtimes without a settings store.
class InMemoryCircuitBreakerPersistence implements ICircuitBreakerPersistence {
  int _failureCount = 0;
  DateTime? _cooldownUntil;

  @override
  int get failureCount => _failureCount;

  @override
  DateTime? get cooldownUntil => _cooldownUntil;

  @override
  Future<void> persistFailure({
    required int failureCount,
    DateTime? cooldownUntil,
  }) async {
    _failureCount = failureCount;
    _cooldownUntil = cooldownUntil;
  }

  @override
  Future<void> clear() async {
    _failureCount = 0;
    _cooldownUntil = null;
  }
}
