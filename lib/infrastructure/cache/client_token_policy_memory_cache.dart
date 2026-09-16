import 'dart:collection';

import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:result_dart/result_dart.dart';

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
  final Map<String, _PendingPolicyResolution> _pending = <String, _PendingPolicyResolution>{};

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
    // Removing the entry makes an already-running lookup stale. The lookup is
    // intentionally not cancellable (SQLite/JWKS may already be in progress),
    // but it can no longer populate or authorize through this cache.
    _pending.remove(credentialHash);
  }

  @override
  void invalidateAll() {
    _entries.clear();
    _pending.clear();
  }

  @override
  bool hasPendingResolution(String credentialHash) => _pending.containsKey(credentialHash);

  @override
  Future<ClientTokenPolicyResolution> resolveSingleFlight(
    String credentialHash,
    Future<Result<ClientTokenPolicy>> Function() loader,
  ) {
    final active = _pending[credentialHash];
    if (active != null) {
      return active.future;
    }

    late final _PendingPolicyResolution pending;
    final future = loader()
        .then((result) {
          final isCurrent = identical(_pending[credentialHash], pending);
          if (isCurrent && result.isSuccess()) {
            final policy = result.getOrNull();
            if (policy != null) {
              put(credentialHash, policy);
            }
          }
          return ClientTokenPolicyResolution(result: result, isCurrent: isCurrent);
        })
        .whenComplete(() {
          if (identical(_pending[credentialHash], pending)) {
            _pending.remove(credentialHash);
          }
        });
    pending = _PendingPolicyResolution(future);
    _pending[credentialHash] = pending;
    return future;
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

class _PendingPolicyResolution {
  const _PendingPolicyResolution(this.future);

  final Future<ClientTokenPolicyResolution> future;
}
