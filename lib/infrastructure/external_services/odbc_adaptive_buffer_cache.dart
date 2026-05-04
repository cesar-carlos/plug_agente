import 'dart:collection';

import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';

/// Remembers larger result-buffer sizes for recurring ODBC queries.
class OdbcAdaptiveBufferCache {
  OdbcAdaptiveBufferCache({
    this.maxEntries = 128,
    Duration? entryTtl,
  }) : entryTtl = entryTtl ?? const Duration(minutes: 30);

  final int maxEntries;
  final Duration entryTtl;
  final LinkedHashMap<String, _AdaptiveBufferCacheEntry> _entries = LinkedHashMap<String, _AdaptiveBufferCacheEntry>();

  int? lookup({
    required String connectionString,
    required String sql,
  }) {
    final key = _cacheKey(connectionString, sql);
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (_isExpired(entry)) {
      return null;
    }

    _entries[key] = entry;
    return entry.bufferBytes;
  }

  void rememberExpandedBuffer({
    required String connectionString,
    required String sql,
    required int currentBufferBytes,
    required String errorMessage,
  }) {
    final expandedBufferBytes = OdbcGatewayBufferExpansion.calculateExpandedBufferBytes(
      currentBufferBytes: currentBufferBytes,
      errorMessage: errorMessage,
    );
    final key = _cacheKey(connectionString, sql);
    _entries.remove(key);
    _entries[key] = _AdaptiveBufferCacheEntry(
      bufferBytes: expandedBufferBytes,
      updatedAt: DateTime.now(),
    );

    _evictExpiredEntries();
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  bool _isExpired(_AdaptiveBufferCacheEntry entry) {
    return DateTime.now().difference(entry.updatedAt) > entryTtl;
  }

  void _evictExpiredEntries() {
    final expiredKeys = _entries.entries
        .where((entry) => _isExpired(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
    expiredKeys.forEach(_entries.remove);
  }

  static String _cacheKey(String connectionString, String sql) {
    final normalizedSql = sql
        .replaceAll(RegExp("'(?:''|[^'])*'"), '?')
        .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\b'), '?')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    return '$connectionString::$normalizedSql';
  }
}

class _AdaptiveBufferCacheEntry {
  const _AdaptiveBufferCacheEntry({
    required this.bufferBytes,
    required this.updatedAt,
  });

  final int bufferBytes;
  final DateTime updatedAt;
}
