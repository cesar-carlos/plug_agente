import 'dart:developer' as developer;

import 'package:plug_agente/application/services/client_token_auth_cache_invalidation.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:result_dart/result_dart.dart';

class DeleteClientToken {
  DeleteClientToken(
    this._repository, {
    ITokenAuditStore? auditStore,
    IAuthorizationDecisionCache? decisionCache,
    IClientTokenPolicyCache? policyCache,
  }) : _auditStore = auditStore,
       _decisionCache = decisionCache,
       _policyCache = policyCache;

  final IClientTokenRepository _repository;
  final ITokenAuditStore? _auditStore;
  final IAuthorizationDecisionCache? _decisionCache;
  final IClientTokenPolicyCache? _policyCache;

  Future<Result<void>> call(String tokenId) async {
    if (tokenId.trim().isEmpty) {
      return Failure(domain.ValidationFailure('tokenId is required'));
    }

    final existing = await _repository.getTokenById(tokenId);
    final result = await _repository.deleteToken(tokenId);
    if (result.isSuccess()) {
      invalidateAuthCachesForClientCredential(
        tokenValue: existing?.tokenValue,
        decisionCache: _decisionCache,
        policyCache: _policyCache,
      );
      await _recordDeleteAuditEvent(tokenId);
    }
    return result;
  }

  Future<void> _recordDeleteAuditEvent(String tokenId) async {
    if (_auditStore == null) {
      return;
    }
    try {
      await _auditStore.record(
        TokenAuditEvent(
          eventType: TokenAuditEventType.delete,
          timestamp: DateTime.now().toUtc(),
          tokenId: tokenId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to record client token delete audit event',
        name: 'delete_client_token_use_case',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
