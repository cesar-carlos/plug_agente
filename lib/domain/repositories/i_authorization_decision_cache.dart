class AuthorizationDecisionCacheEntry {
  const AuthorizationDecisionCacheEntry({
    required this.allowed,
    required this.expiresAt,
    this.clientId,
    this.reason,
    this.requestId,
    this.method,
  });

  final bool allowed;
  final DateTime expiresAt;
  final String? clientId;
  final String? reason;
  final String? requestId;
  final String? method;

  bool get isExpired => isExpiredAt(DateTime.now());

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

abstract class IAuthorizationDecisionCache {
  /// Changes on explicit invalidation so pending authorizations can discard
  /// policies resolved before a credential mutation.
  int get revision;

  AuthorizationDecisionCacheEntry? get(String key);

  void put(String key, AuthorizationDecisionCacheEntry entry);

  void invalidate(String key);

  /// Removes all entries whose key starts with [credentialHash] + '|'.
  void invalidateForCredentialHash(String credentialHash);

  void invalidateAll();
}
