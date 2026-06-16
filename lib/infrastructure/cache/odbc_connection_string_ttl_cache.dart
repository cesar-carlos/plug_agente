class _TimedConnectionStringEntry {
  const _TimedConnectionStringEntry({
    required this.connectionString,
    required this.cachedAt,
  });

  final String connectionString;
  final DateTime cachedAt;
}

/// Short-TTL cache for resolved ODBC connection strings on gateway hot paths.
final class OdbcConnectionStringTtlCache {
  OdbcConnectionStringTtlCache({
    Duration ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _ttl = ttl,
       _clock = clock ?? DateTime.now;

  final Duration _ttl;
  final DateTime Function() _clock;
  final Map<String, _TimedConnectionStringEntry> _entries = {};

  String resolve({
    required String cacheKey,
    required String Function() compute,
  }) {
    final now = _clock();
    final cached = _entries[cacheKey];
    if (cached != null && now.difference(cached.cachedAt) < _ttl) {
      return cached.connectionString;
    }

    final resolved = compute();
    _entries[cacheKey] = _TimedConnectionStringEntry(
      connectionString: resolved,
      cachedAt: now,
    );
    return resolved;
  }

  void invalidate() {
    _entries.clear();
  }
}
