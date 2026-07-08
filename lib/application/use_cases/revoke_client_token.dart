import 'dart:developer' as developer;

import 'package:plug_agente/application/services/client_token_auth_cache_invalidation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class RevokeClientToken {
  RevokeClientToken(
    this._repository, {
    ITokenAuditStore? auditStore,
    IAuthorizationDecisionCache? decisionCache,
    IClientTokenPolicyCache? policyCache,
    IRevokedTokenStore? revokedTokenStore,
    FeatureFlags? featureFlags,
  }) : _auditStore = auditStore,
       _decisionCache = decisionCache,
       _policyCache = policyCache,
       _revokedTokenStore = revokedTokenStore,
       _featureFlags = featureFlags;

  final IClientTokenRepository _repository;
  final ITokenAuditStore? _auditStore;
  final IAuthorizationDecisionCache? _decisionCache;
  final IClientTokenPolicyCache? _policyCache;
  final IRevokedTokenStore? _revokedTokenStore;
  final FeatureFlags? _featureFlags;

  Future<Result<void>> call(String tokenId) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('tokenId is required'));
    }

    final tokenValue = await loadClientTokenSecretForCacheInvalidation(
      repository: _repository,
      tokenId: tokenId,
      logName: 'revoke_client_token_use_case',
    );
    final result = await _repository.revokeToken(tokenId);
    if (result.isSuccess()) {
      invalidateAuthCachesForClientCredential(
        tokenValue: tokenValue,
        decisionCache: _decisionCache,
        policyCache: _policyCache,
      );
      _recordRevokedTokenInSession(tokenValue);
      await _recordRevokeAuditEvent(tokenId);
    }
    return result;
  }

  void _recordRevokedTokenInSession(String? tokenValue) {
    final trimmed = tokenValue?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return;
    }
    final featureFlags = _featureFlags;
    final revokedTokenStore = _revokedTokenStore;
    if (featureFlags == null || revokedTokenStore == null || !featureFlags.enableSocketRevokedTokenInSession) {
      return;
    }
    revokedTokenStore.add(trimmed);
  }

  Future<void> _recordRevokeAuditEvent(String tokenId) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.revoke,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to record client token revoke audit event',
        name: 'revoke_client_token_use_case',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
