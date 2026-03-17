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

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

abstract class IAuthorizationDecisionCache {
  AuthorizationDecisionCacheEntry? get(String key);

  void put(String key, AuthorizationDecisionCacheEntry entry);

  void invalidate(String key);

  void invalidateAll();
}
