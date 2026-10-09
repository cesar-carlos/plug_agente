import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_authorization_trust_invalidator.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';

class AuthorizationTrustInvalidator implements IAuthorizationTrustInvalidator {
  AuthorizationTrustInvalidator({
    required IAuthorizationDecisionCache decisionCache,
    required IClientTokenPolicyCache policyCache,
    required JwtJwksVerifier verifier,
  }) : _decisionCache = decisionCache,
       _policyCache = policyCache,
       _verifier = verifier;

  final IAuthorizationDecisionCache _decisionCache;
  final IClientTokenPolicyCache _policyCache;
  final JwtJwksVerifier _verifier;

  @override
  void invalidate() {
    _decisionCache.invalidateAll();
    _policyCache.invalidateAll();
    _verifier.invalidateTrust();
  }
}
