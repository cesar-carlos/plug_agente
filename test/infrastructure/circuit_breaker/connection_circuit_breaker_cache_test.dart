import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';
import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker_cache.dart';

ConnectionCircuitBreaker _newBreaker() {
  return ConnectionCircuitBreaker(
    failureThreshold: 3,
    resetTimeout: const Duration(seconds: 30),
  );
}

void main() {
  group('ConnectionCircuitBreakerCache', () {
    test('should return the same breaker on repeated calls with the same key', () {
      final cache = ConnectionCircuitBreakerCache(factory: _newBreaker);

      final first = cache.getOrCreate('dsn=a');
      final second = cache.getOrCreate('dsn=a');

      expect(identical(first, second), isTrue);
      expect(cache.size, 1);
    });

    test('should create a distinct breaker per connection string', () {
      final cache = ConnectionCircuitBreakerCache(factory: _newBreaker);

      final a = cache.getOrCreate('dsn=a');
      final b = cache.getOrCreate('dsn=b');

      expect(identical(a, b), isFalse);
      expect(cache.size, 2);
    });

    test('should evict the least recently used breaker when at capacity', () {
      final cache = ConnectionCircuitBreakerCache(
        factory: _newBreaker,
        maxSize: 2,
      );

      final first = cache.getOrCreate('dsn=a');
      cache.getOrCreate('dsn=b');
      cache.getOrCreate('dsn=c'); // Evicts 'dsn=a'.

      expect(cache.size, 2);
      // Re-creating 'dsn=a' should not return the original instance because
      // it was evicted.
      final aRecreated = cache.getOrCreate('dsn=a');
      expect(identical(first, aRecreated), isFalse);
    });

    test('should preserve recently-used entries across capacity overflow', () {
      final cache = ConnectionCircuitBreakerCache(
        factory: _newBreaker,
        maxSize: 2,
      );

      final first = cache.getOrCreate('dsn=a');
      cache.getOrCreate('dsn=b');
      // Touch 'dsn=a' so it moves to the most-recently-used slot.
      cache.getOrCreate('dsn=a');
      cache.getOrCreate('dsn=c'); // Evicts 'dsn=b', not 'dsn=a'.

      final aStillThere = cache.getOrCreate('dsn=a');
      expect(identical(first, aStillThere), isTrue);
    });

    test('should reset the breaker without removing it from the cache', () {
      final cache = ConnectionCircuitBreakerCache(factory: _newBreaker);
      final breaker = cache.getOrCreate('dsn=a');

      final reset = cache.reset('dsn=a');

      expect(reset, isTrue);
      expect(identical(cache.getOrCreate('dsn=a'), breaker), isTrue);
    });

    test('should return false when resetting an unknown key', () {
      final cache = ConnectionCircuitBreakerCache(factory: _newBreaker);

      expect(cache.reset('dsn=missing'), isFalse);
    });

    test('clear should drop every cached breaker', () {
      final cache = ConnectionCircuitBreakerCache(factory: _newBreaker);
      cache.getOrCreate('dsn=a');
      cache.getOrCreate('dsn=b');

      cache.clear();

      expect(cache.size, 0);
    });

    test('should reject non-positive maxSize', () {
      expect(
        () => ConnectionCircuitBreakerCache(factory: _newBreaker, maxSize: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ConnectionCircuitBreakerCache(factory: _newBreaker, maxSize: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('in-flight reference survives eviction', () {
      // Eviction is safe because callers hold a direct reference to the breaker
      // returned by getOrCreate; the cache only drops its own bookkeeping.
      final cache = ConnectionCircuitBreakerCache(
        factory: _newBreaker,
        maxSize: 1,
      );
      final inFlight = cache.getOrCreate('dsn=a');
      cache.getOrCreate('dsn=b'); // Evicts 'dsn=a' from the map.

      // The in-flight reference is still valid and usable.
      expect(inFlight.state, CircuitState.closed);
      inFlight.reset(); // Should not throw.
    });
  });
}
