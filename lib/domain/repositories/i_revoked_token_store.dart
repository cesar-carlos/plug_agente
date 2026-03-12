/// Store for revoked tokens within an active session.
///
/// When a token is determined revoked (e.g. payload.revoked or policy.isRevoked),
/// it is added here so subsequent requests with the same token are rejected
/// immediately without full revalidation.
abstract class IRevokedTokenStore {
  /// Returns true if [token] is in the revoked set.
  bool isRevoked(String token);

  /// Adds [token] to the revoked set for the session TTL.
  void add(String token);
}
