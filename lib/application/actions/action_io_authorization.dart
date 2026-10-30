import 'dart:convert';

import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/core/utils/jwt_numeric_date.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/entities/agent_action_authorization_scopes.dart';
import 'package:plug_agente/domain/entities/client_token_policy_agent_action_authorization.dart';
import 'package:plug_agente/domain/entities/client_token_runtime_restrictions.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:result_dart/result_dart.dart';

enum ActionIoOperation {
  run,
  validateRun,
  sendInput,
  closeInput,
  getInputStatus,
  readIo,
  getExecution,
  findExecution,
  cancel,
}

final class ActionIoPrincipal {
  const ActionIoPrincipal({required this.clientId, required this.agentId, required this.tokenId});

  final String clientId;
  final String agentId;
  final String tokenId;
}

/// Resolves current local authority on every call, independently of legacy flags/caches.
final class ActionIoAuthorization {
  ActionIoAuthorization(this._repository, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final IClientTokenRepository _repository;
  final DateTime Function() _now;

  Future<Result<ActionIoPrincipal>> authorize({
    required String credential,
    required String agentId,
    required String actionId,
    required ActionIoOperation operation,
    String? ownerClientId,
  }) async {
    final token = normalizeClientCredentialToken(credential);
    if (token.isEmpty || agentId.trim().isEmpty || actionId.trim().isEmpty) {
      return Failure(_denied('missing_identity'));
    }
    final lookup = await _repository.getTokenPolicySummaryByHash(hashClientCredentialToken(token));
    if (lookup.isError()) return Failure(lookup.exceptionOrNull()!);
    final record = lookup.getOrThrow();
    if (record.isRevoked || record.hasInvalidPolicy || record.id.isEmpty) {
      return Failure(_denied('inactive_credential'));
    }
    if (record.clientId.trim().isEmpty || record.agentId != agentId) {
      return Failure(_denied('agent_binding_required'));
    }
    if (ownerClientId != null && ownerClientId != record.clientId) {
      return Failure(_denied('execution_owner_mismatch'));
    }
    if (!_validLifetime(token)) return Failure(_denied('credential_lifetime_invalid'));
    if (!ClientTokenRuntimeRestrictions.isValidPayload(record.payload)) {
      return Failure(_denied('invalid_policy'));
    }
    final restrictions = ClientTokenRuntimeRestrictions.fromPayload(record.payload);
    if (!restrictions.declaresAgentActionMetadata) return Failure(_denied('explicit_scope_required'));
    final scope = switch (operation) {
      ActionIoOperation.run ||
      ActionIoOperation.sendInput ||
      ActionIoOperation.closeInput => AgentActionAuthorizationScopes.run,
      ActionIoOperation.validateRun => AgentActionAuthorizationScopes.validateRun,
      ActionIoOperation.cancel => AgentActionAuthorizationScopes.cancel,
      ActionIoOperation.getExecution ||
      ActionIoOperation.getInputStatus ||
      ActionIoOperation.readIo ||
      ActionIoOperation.findExecution => AgentActionAuthorizationScopes.readExecution,
    };
    for (final requiredScope in [AgentActionAuthorizationScopes.io, scope]) {
      if (!ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
        policyPayload: record.payload,
        requiredScope: requiredScope,
        actionId: actionId,
      )) {
        return Failure(_denied('scope_or_action_denied'));
      }
    }
    return Success(ActionIoPrincipal(clientId: record.clientId, agentId: agentId, tokenId: record.id));
  }

  bool _validLifetime(String locallyVerifiedCredential) {
    final parts = locallyVerifiedCredential.split('.');
    if (parts.length != 3) return true;
    // Hash lookup has authenticated the exact credential; JWT parsing only narrows lifetime.
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is! Map<String, dynamic>) return false;
      final expiration = parseJwtNumericDate(payload['exp'], claim: 'exp');
      final notBefore = parseJwtNumericDate(payload['nbf'], claim: 'nbf');
      final now = _now();
      return (expiration == null || now.isBefore(expiration)) && (notBefore == null || !now.isBefore(notBefore));
    } on FormatException {
      return false;
    }
  }

  ActionAuthorizationFailure _denied(String reason) => ActionAuthorizationFailure.withContext(
    message: 'The current local credential does not authorize this I/O operation.',
    code: 'ACTION_IO_UNAUTHORIZED',
    context: {'reason': reason, 'retryable': false, 'effects_possible': false},
  );
}
