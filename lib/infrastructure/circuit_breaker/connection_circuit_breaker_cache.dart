import 'dart:collection';

import 'package:plug_agente/infrastructure/circuit_breaker/connection_circuit_breaker.dart';

/// LRU-bounded cache of [ConnectionCircuitBreaker] keyed by connection string.
///
/// The plain `Map<String, ConnectionCircuitBreaker>` pattern previously used
/// by `OdbcDatabaseGateway` and `OdbcStreamingGateway` grew monotonically with
/// distinct connection strings (credential rotation, multi-config sessions,
/// etc.). This cache caps the working set with last-touched LRU eviction so
/// the few connection strings actually in use keep their failure memory while
/// long-tail strings do not leak.
///
/// Eviction is safe: existing callers hold a direct reference to the breaker
/// returned by [getOrCreate], so an in-flight execution cannot have its
/// breaker yanked. The next call for an evicted key simply creates a fresh
/// breaker, losing only the accumulated failure counter for that key.
class ConnectionCircuitBreakerCache {
  ConnectionCircuitBreakerCache({
    required ConnectionCircuitBreaker Function() factory,
    int maxSize = _defaultMaxSize,
  }) : assert(maxSize > 0, 'maxSize must be greater than zero'),
       _factory = factory,
       _maxSize = maxSize;

  /// Default cap. Empirically, desktop sessions use 1–4 distinct connection
  /// strings concurrently; 16 gives headroom for credential rotation and
  /// multi-config workflows without unbounded growth.
  static const int _defaultMaxSize = 16;

  final ConnectionCircuitBreaker Function() _factory;
  final int _maxSize;
  // LinkedHashMap preserves insertion order; we re-insert on access so the
  // tail of the map is the most recently used entry and the head is the
  // least recently used.
  final LinkedHashMap<String, ConnectionCircuitBreaker> _entries = LinkedHashMap<String, ConnectionCircuitBreaker>();

  /// Number of breakers currently cached. Exposed for diagnostics.
  int get size => _entries.length;

  /// Maximum number of breakers retained before LRU eviction kicks in.
  int get maxSize => _maxSize;

  /// Returns the breaker for [connectionString], creating one if needed and
  /// evicting the least recently used entry when the cache is at capacity.
  ConnectionCircuitBreaker getOrCreate(String connectionString) {
    final existing = _entries.remove(connectionString);
    if (existing != null) {
      _entries[connectionString] = existing;
      return existing;
    }

    if (_entries.length >= _maxSize) {
      _entries.remove(_entries.keys.first);
    }

    final created = _factory();
    _entries[connectionString] = created;
    return created;
  }

  /// Resets the breaker for [connectionString] without removing it from the
  /// cache. Returns `true` when a breaker was found, `false` otherwise.
  bool reset(String connectionString) {
    final breaker = _entries[connectionString];
    if (breaker == null) {
      return false;
    }
    breaker.reset();
    return true;
  }

  /// Drops every cached breaker. Callers should invoke this on configuration
  /// reset, full disconnect, or when in-flight references are guaranteed to
  /// have completed.
  void clear() {
    _entries.clear();
  }
}
