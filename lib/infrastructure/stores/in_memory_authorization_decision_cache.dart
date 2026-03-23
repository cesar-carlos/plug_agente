import 'dart:collection';

import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';

/// In-memory LRU-bounded cache: [get] refreshes recency; evicts oldest when
/// over [maxEntries].
class InMemoryAuthorizationDecisionCache implements IAuthorizationDecisionCache {
  InMemoryAuthorizationDecisionCache({this.maxEntries = 8192})
    : _entries = LinkedHashMap<String, AuthorizationDecisionCacheEntry>();

  final int maxEntries;
  final LinkedHashMap<String, AuthorizationDecisionCacheEntry> _entries;

  /// Maps credential hash (key prefix before '|') to cache keys for that
  /// credential. Keeps [invalidateForCredentialHash] off a full key scan.
  final Map<String, Set<String>> _keysByCredentialHash = <String, Set<String>>{};

  static String? _credentialHashForKey(String key) {
    final pipe = key.indexOf('|');
    if (pipe <= 0) {
      return null;
    }
    return key.substring(0, pipe);
  }

  void _addKeyToCredentialIndex(String key) {
    final hash = _credentialHashForKey(key);
    if (hash == null) {
      return;
    }
    _keysByCredentialHash.putIfAbsent(hash, () => <String>{}).add(key);
  }

  void _removeKeyFromCredentialIndex(String key) {
    final hash = _credentialHashForKey(key);
    if (hash == null) {
      return;
    }
    final set = _keysByCredentialHash[hash];
    if (set == null) {
      return;
    }
    set.remove(key);
    if (set.isEmpty) {
      _keysByCredentialHash.remove(hash);
    }
  }

  @override
  AuthorizationDecisionCacheEntry? get(String key) {
    final entry = _entries.remove(key);
    if (entry == null) {
      return null;
    }
    if (entry.isExpired) {
      _removeKeyFromCredentialIndex(key);
      return null;
    }
    _entries[key] = entry;
    return entry;
  }

  @override
  void put(String key, AuthorizationDecisionCacheEntry entry) {
    final existed = _entries.containsKey(key);
    _entries.remove(key);
    _entries[key] = entry;
    if (!existed) {
      _addKeyToCredentialIndex(key);
    }
    _evictExcess();
  }

  void _evictExcess() {
    while (_entries.length > maxEntries) {
      final key = _entries.keys.first;
      _removeKeyFromCredentialIndex(key);
      _entries.remove(key);
    }
  }

  @override
  void invalidate(String key) {
    final removed = _entries.remove(key);
    if (removed != null) {
      _removeKeyFromCredentialIndex(key);
    }
  }

  @override
  void invalidateForCredentialHash(String credentialHash) {
    final keys = _keysByCredentialHash.remove(credentialHash);
    if (keys == null) {
      return;
    }
    keys.forEach(_entries.remove);
  }

  @override
  void invalidateAll() {
    _entries.clear();
    _keysByCredentialHash.clear();
  }
}
