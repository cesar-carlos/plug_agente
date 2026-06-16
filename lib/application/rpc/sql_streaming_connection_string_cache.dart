import 'package:plug_agente/application/rpc/sql_streaming_connection_string_resolver.dart';
import 'package:plug_agente/domain/entities/config.dart';

class _TimedConnectionStringEntry {
  const _TimedConnectionStringEntry({
    required this.connectionString,
    required this.cachedAt,
  });

  final String connectionString;
  final DateTime cachedAt;
}

/// Short-TTL cache for resolved streaming ODBC connection strings.
final class SqlStreamingConnectionStringCache {
  SqlStreamingConnectionStringCache({
    Duration ttl = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _ttl = ttl,
       _clock = clock ?? DateTime.now;

  final Duration _ttl;
  final DateTime Function() _clock;
  final Map<String, _TimedConnectionStringEntry> _entries = {};

  String resolve({
    required Config config,
    String? databaseOverride,
  }) {
    final override = databaseOverride?.trim() ?? '';
    final cacheKey = '${config.id}:${config.updatedAt.millisecondsSinceEpoch}:$override';
    final now = _clock();
    final cached = _entries[cacheKey];
    if (cached != null && now.difference(cached.cachedAt) < _ttl) {
      return cached.connectionString;
    }

    final resolved = resolveSqlStreamingConnectionString(
      config,
      databaseOverride: databaseOverride,
    );
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
