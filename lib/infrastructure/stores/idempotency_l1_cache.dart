import 'dart:collection';

import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';

class _IdempotencyL1Entry {
  _IdempotencyL1Entry({
    required this.record,
    required this.expiresAt,
  });

  final IdempotencyRecord record;
  final DateTime expiresAt;
}

/// Small in-memory L1 in front of the persisted idempotency store.
///
/// Hot keys are served without SQLite I/O; entries expire with the same TTL
/// as the backing store write.
class IdempotencyL1Cache {
  IdempotencyL1Cache({
    this.maxEntries = 256,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final int maxEntries;
  final DateTime Function() _nowProvider;

  final LinkedHashMap<String, _IdempotencyL1Entry> _entries = LinkedHashMap<String, _IdempotencyL1Entry>();

  IdempotencyRecord? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.expiresAt.isBefore(_nowProvider())) {
      return null;
    }
    _entries[key] = entry;
    return entry.record;
  }

  void put(String key, IdempotencyRecord record, DateTime expiresAt) {
    _entries.remove(key);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = _IdempotencyL1Entry(record: record, expiresAt: expiresAt);
  }

  void invalidate(String key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }
}
