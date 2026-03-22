import 'dart:collection';

import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';

/// In-memory LRU-bounded cache: [get] refreshes recency; evicts oldest when
/// over [maxEntries].
class InMemoryAuthorizationDecisionCache implements IAuthorizationDecisionCache {
  InMemoryAuthorizationDecisionCache({this.maxEntries = 8192})
    : _entries = LinkedHashMap<String, AuthorizationDecisionCacheEntry>();

  final int maxEntries;
  final LinkedHashMap<String, AuthorizationDecisionCacheEntry> _entries;

  @override
  AuthorizationDecisionCacheEntry? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.isExpired) {
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
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  void invalidate(String key) {
    _entries.remove(key);
  }

  @override
  void invalidateForCredentialHash(String credentialHash) {
    final prefix = '$credentialHash|';
    final toRemove = _entries.keys.where((String k) => k.startsWith(prefix)).toList();
    toRemove.forEach(_entries.remove);
  }

  @override
  void invalidateAll() {
    _entries.clear();
  }
}
