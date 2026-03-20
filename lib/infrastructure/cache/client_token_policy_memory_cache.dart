import 'dart:collection';

import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';

/// In-memory TTL cache for resolved [ClientTokenPolicy] by credential hash.
///
/// Cleared when client tokens are updated, revoked, or deleted (same time as
/// the authorization decision cache). Bounded by [maxEntries] (LRU).
class ClientTokenPolicyMemoryCache implements IClientTokenPolicyCache {
  ClientTokenPolicyMemoryCache({
    Duration ttl = const Duration(seconds: 30),
    this.maxEntries = 2048,
  }) : _ttl = ttl,
       _entries = LinkedHashMap<String, _PolicyCacheEntry>();

  final Duration _ttl;
  final int maxEntries;
  final LinkedHashMap<String, _PolicyCacheEntry> _entries;

  @override
  ClientTokenPolicy? get(String credentialHash) {
    final entry = _entries.remove(credentialHash);
    if (entry == null) {
      return null;
    }
    if (DateTime.now().isAfter(entry.expiresAt)) {
      return null;
    }
    _entries[credentialHash] = entry;
    return entry.policy;
  }

  @override
  void put(String credentialHash, ClientTokenPolicy policy) {
    _entries.remove(credentialHash);
    _entries[credentialHash] = _PolicyCacheEntry(
      policy: policy,
      expiresAt: DateTime.now().add(_ttl),
    );
    _evictExcess();
  }

  void _evictExcess() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  @override
  void invalidate(String credentialHash) {
    _entries.remove(credentialHash);
  }

  @override
  void invalidateAll() {
    _entries.clear();
  }
}

class _PolicyCacheEntry {
  _PolicyCacheEntry({
    required this.policy,
    required this.expiresAt,
  });

  final ClientTokenPolicy policy;
  final DateTime expiresAt;
}
