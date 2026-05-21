/// Stable `failure.context['reason']` / audit metadata for client token and SQL authorization flows.
abstract final class AuthorizationContextConstants {
  static const String tokenRevokedReason = 'token_revoked';

  static const String tokenNotFoundReason = 'token_not_found';

  static const String invalidTokenSignatureReason = 'invalid_token_signature';

  static const String invalidPolicyReason = 'invalid_policy';

  static const String unauthorizedReason = 'unauthorized';

  static const String jwksCircuitOpenReason = 'jwks_circuit_open';

  static const String invalidJwksConfigReason = 'invalid_jwks_config';

  static const String tokenExpiredReason = 'token_expired';

  static const String tokenNotYetValidReason = 'token_not_yet_valid';

  static const String tokenVersionConflictReason = 'token_version_conflict';

  static const String authorizationDeniedReason = 'authorization_denied';

  static const String unexpectedFailureTypeReason = 'unexpected_failure_type';

  static const String databaseRequiredReason = 'database_required';

  static const String databaseMismatchReason = 'database_mismatch';

  static const String missingPermissionReason = 'missing_permission';
}
