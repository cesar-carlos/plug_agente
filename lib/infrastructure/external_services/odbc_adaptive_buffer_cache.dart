import 'dart:collection';

import 'package:plug_agente/infrastructure/external_services/odbc_gateway_buffer_expansion.dart';

/// Remembers larger result-buffer sizes for recurring ODBC queries.
class OdbcAdaptiveBufferCache {
  OdbcAdaptiveBufferCache({this.maxEntries = 128});

  final int maxEntries;
  final LinkedHashMap<String, int> _entries = LinkedHashMap<String, int>();

  int? lookup({
    required String connectionString,
    required String sql,
  }) {
    final key = _cacheKey(connectionString, sql);
    final value = _entries.remove(key);
    if (value == null) {
      return null;
    }

    _entries[key] = value;
    return value;
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
    _entries[key] = expandedBufferBytes;

    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
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
