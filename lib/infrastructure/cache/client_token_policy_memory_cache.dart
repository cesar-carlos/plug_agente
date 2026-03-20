import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';

/// In-memory TTL cache for resolved [ClientTokenPolicy] by credential hash.
///
/// Cleared when client tokens are updated, revoked, or deleted (same time as
/// the authorization decision cache).
class ClientTokenPolicyMemoryCache implements IClientTokenPolicyCache {
  ClientTokenPolicyMemoryCache({
    Duration ttl = const Duration(seconds: 30),
  }) : _ttl = ttl;

  final Duration _ttl;
  final Map<String, _PolicyCacheEntry> _entries = <String, _PolicyCacheEntry>{};

  @override
  ClientTokenPolicy? get(String credentialHash) {
    final entry = _entries[credentialHash];
    if (entry == null) {
      return null;
    }
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _entries.remove(credentialHash);
      return null;
    }
    return entry.policy;
  }

  @override
  void put(String credentialHash, ClientTokenPolicy policy) {
    _entries[credentialHash] = _PolicyCacheEntry(
      policy: policy,
      expiresAt: DateTime.now().add(_ttl),
    );
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
