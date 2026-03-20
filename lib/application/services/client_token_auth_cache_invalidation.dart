import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';

/// Drops decision/policy cache entries for one credential, or full flush if the
/// secret is unavailable (safe fallback).
void invalidateAuthCachesForClientCredential({
  required String? tokenValue,
  IAuthorizationDecisionCache? decisionCache,
  IClientTokenPolicyCache? policyCache,
}) {
  final trimmed = tokenValue?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    decisionCache?.invalidateAll();
    policyCache?.invalidateAll();
    return;
  }
  final hash = hashClientCredentialToken(trimmed);
  decisionCache?.invalidateForCredentialHash(hash);
  policyCache?.invalidate(hash);
}
