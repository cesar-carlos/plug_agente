import 'dart:developer' as developer;

import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';

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

Future<String?> loadClientTokenSecretForCacheInvalidation({
  required IClientTokenRepository repository,
  required String tokenId,
  required String logName,
}) async {
  final secretResult = await repository.getTokenSecret(tokenId);
  return secretResult.fold(
    (lookup) => lookup.tokenValue,
    (failure) {
      final message = failure is domain.Failure ? failure.message : failure.toString();
      final cause = failure is domain.Failure ? failure.cause : failure;
      developer.log(
        'Client token secret unavailable for cache invalidation: $message',
        name: logName,
        error: cause,
      );
      return null;
    },
  );
}
