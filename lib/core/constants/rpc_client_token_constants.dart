/// Stable `error.data.reason` / diagnostic strings for client-token JSON-RPC flows.
abstract final class RpcClientTokenConstants {
  /// Hub omitted `client_token` while `enableClientTokenAuthorization` is on.
  static const String missingClientTokenReason = 'missing_client_token';

  /// `client_token.getPolicy` rejected because `enableClientTokenAuthorization` is off.
  static const String clientTokenAuthorizationDisabledRpcReason = 'client_token_authorization_disabled';

  /// `client_token.getPolicy` rejected because `enableClientTokenPolicyIntrospection` is off.
  static const String clientTokenIntrospectionDisabledRpcReason = 'client_token_introspection_disabled';

  /// `client_token.getPolicy` exceeded the per-agent credential rate limit.
  static const String clientTokenGetPolicyRateLimitedReason = 'client_token_get_policy_rate_limited';
}
