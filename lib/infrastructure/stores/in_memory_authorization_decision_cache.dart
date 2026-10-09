import 'dart:collection';

import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';

/// In-memory LRU-bounded cache: [get] refreshes recency; evicts oldest when
/// over [maxEntries].
class InMemoryAuthorizationDecisionCache implements IAuthorizationDecisionCache {
  InMemoryAuthorizationDecisionCache({this.maxEntries = 8192, DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _entries = LinkedHashMap<String, AuthorizationDecisionCacheEntry>();

  int _revision = 0;
  @override
  int get revision => _revision;

  final int maxEntries;
  final DateTime Function() _now;
  final LinkedHashMap<String, AuthorizationDecisionCacheEntry> _entries;

  @override
  AuthorizationDecisionCacheEntry? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.isExpiredAt(_now())) {
      return null;
    }
    _entries[key] = entry;
    return entry;
  }

  @override
  void put(String key, AuthorizationDecisionCacheEntry entry) {
    _entries.remove(key);
    _entries[key] = entry;
    _evictExcess();
  }

  void _evictExcess() {
    // First pass: remove expired entries so they don't count toward the cap
    // or occupy slots that could hold live decisions. The LRU get() removes
    // expired entries on access, but entries that are never re-read would
    // otherwise stay until count-based eviction.
    if (_entries.length > maxEntries) {
      final now = _now();
      _entries.removeWhere((_, e) => e.isExpiredAt(now));
    }
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  void invalidate(String key) {
    _revision++;
    _entries.remove(key);
  }

  @override
  void invalidateForCredentialHash(String credentialHash) {
    _revision++;
    final prefix = '$credentialHash|';
    final toRemove = _entries.keys.where((k) => k.startsWith(prefix)).toList();
    toRemove.forEach(_entries.remove);
  }

  @override
  void invalidateAll() {
    _revision++;
    _entries.clear();
  }
}
