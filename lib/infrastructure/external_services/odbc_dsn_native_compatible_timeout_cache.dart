import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Remembers query timeouts that were compatible with the native ODBC pool for a
/// given connection string (DSN).
///
/// Used by the native-compatible acquire policy to allow the native-compatible
/// acquire path when callers pass an explicit timeout that matches the configured
/// default or a previously observed compatible timeout for the same DSN.
final class OdbcDsnNativeCompatibleTimeoutCache {
  OdbcDsnNativeCompatibleTimeoutCache({
    Duration ttl = const Duration(minutes: 10),
    int maxEntriesPerDsn = 8,
  }) : _ttl = ttl,
       _maxEntriesPerDsn = maxEntriesPerDsn;

  final Duration _ttl;
  final int _maxEntriesPerDsn;
  final Map<String, _DsnTimeoutEntry> _entries = <String, _DsnTimeoutEntry>{};

  bool isCompatible({
    required String connectionString,
    required Duration timeout,
    required Duration defaultQueryTimeout,
  }) {
    if (timeout == defaultQueryTimeout) {
      return true;
    }

    final entry = _entries[_dsnKey(connectionString)];
    if (entry == null || entry.isExpired(_ttl)) {
      return false;
    }
    return entry.timeoutsMs.contains(timeout.inMilliseconds);
  }

  void remember({
    required String connectionString,
    required Duration timeout,
  }) {
    final key = _dsnKey(connectionString);
    final existing = _entries[key];
    final timeoutsMs = existing == null || existing.isExpired(_ttl)
        ? <int>{}
        : Set<int>.from(existing.timeoutsMs);
    timeoutsMs.add(timeout.inMilliseconds);
    while (timeoutsMs.length > _maxEntriesPerDsn) {
      final oldest = timeoutsMs.first;
      timeoutsMs.remove(oldest);
    }
    _entries[key] = _DsnTimeoutEntry(
      timeoutsMs: timeoutsMs,
      recordedAt: DateTime.now(),
    );
  }

  String _dsnKey(String connectionString) {
    return sha256.convert(utf8.encode(connectionString.trim())).toString();
  }
}

final class _DsnTimeoutEntry {
  const _DsnTimeoutEntry({
    required this.timeoutsMs,
    required this.recordedAt,
  });

  final Set<int> timeoutsMs;
  final DateTime recordedAt;

  bool isExpired(Duration ttl) => DateTime.now().difference(recordedAt) > ttl;
}
