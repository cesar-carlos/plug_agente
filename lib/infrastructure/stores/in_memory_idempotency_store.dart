import 'dart:collection';

import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';

/// In-memory idempotency store with TTL.
///
/// Entries expire after the configured TTL and are cleaned up on access.
class InMemoryIdempotencyStore implements IIdempotencyStore {
  InMemoryIdempotencyStore({
    Duration? defaultTtl,
    int? maxEntries,
    DateTime Function()? nowProvider,
  }) : _defaultTtl = defaultTtl ?? const Duration(minutes: 5),
       _maxEntries = maxEntries ?? 1000,
       _nowProvider = nowProvider ?? DateTime.now {
    if (_maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 1');
    }
  }

  final Duration _defaultTtl;
  final int _maxEntries;
  final DateTime Function() _nowProvider;

  final LinkedHashMap<String, _Entry> _store = LinkedHashMap<String, _Entry>();

  @override
  IdempotencyRecord? getRecord(String key) {
    _evictExpiredEntries();
    final entry = _store[key];
    if (entry == null) return null;
    if (_nowProvider().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    _markAsRecentlyUsed(key, entry);
    return IdempotencyRecord(
      response: entry.response,
      requestFingerprint: entry.requestFingerprint,
    );
  }

  @override
  RpcResponse? get(String key) {
    return getRecord(key)?.response;
  }

  @override
  void set(
    String key,
    RpcResponse response,
    Duration ttl, {
    String? requestFingerprint,
  }) {
    _evictExpiredEntries();
    if (_store.containsKey(key)) {
      _store.remove(key);
    } else {
      _evictLeastRecentlyUsedIfNeeded();
    }
    final effectiveTtl = ttl == Duration.zero ? _defaultTtl : ttl;
    _store[key] = _Entry(
      response: response,
      requestFingerprint: requestFingerprint,
      expiresAt: _nowProvider().add(effectiveTtl),
    );
  }

  void _markAsRecentlyUsed(String key, _Entry entry) {
    _store.remove(key);
    _store[key] = entry;
  }

  void _evictLeastRecentlyUsedIfNeeded() {
    while (_store.length >= _maxEntries && _store.isNotEmpty) {
      _store.remove(_store.keys.first);
    }
  }

  void _evictExpiredEntries() {
    final now = _nowProvider();
    final expiredKeys = _store.entries
        .where((entry) => now.isAfter(entry.value.expiresAt))
        .map((entry) => entry.key)
        .toList(growable: false);
    expiredKeys.forEach(_store.remove);
  }
}

class _Entry {
  _Entry({
    required this.response,
    required this.expiresAt,
    required this.requestFingerprint,
  });
  final RpcResponse response;
  final DateTime expiresAt;
  final String? requestFingerprint;
}
