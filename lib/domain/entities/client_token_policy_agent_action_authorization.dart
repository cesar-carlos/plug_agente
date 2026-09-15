import 'package:plug_agente/domain/entities/agent_action_authorization_scopes.dart';
import 'package:plug_agente/domain/entities/client_token_runtime_restrictions.dart';

/// Interprets hub-issued `ClientTokenPolicy.payload` for remote `agent.action.*`
/// when `enableClientTokenAuthorization` is on, per `socket_communication_standard.md`.
abstract final class ClientTokenPolicyAgentActionAuthorization {
  /// When false, scope/allowlist checks are skipped (legacy tokens without agent-action metadata).
  static bool payloadDeclaresAgentActionScopeMetadata(Map<String, dynamic> payload) {
    return ClientTokenRuntimeRestrictions.fromPayload(payload).declaresAgentActionMetadata;
  }

  /// Returns whether the policy payload authorizes the RPC for [requiredScope] and [actionId].
  ///
  /// [actionId] is the definition id for run/validate, or the execution's `action_id` for
  /// cancel/getExecution when allowlist applies.
  static bool grantsRemoteAgentAction({
    required Map<String, dynamic> policyPayload,
    required String requiredScope,
    required String actionId,
  }) {
    if (!payloadDeclaresAgentActionScopeMetadata(policyPayload)) {
      return true;
    }
    final restrictions = ClientTokenRuntimeRestrictions.fromPayload(policyPayload);
    final granted = restrictions.agentActionScopes;
    if (granted.isEmpty) {
      return false;
    }
    final normalizedRequired = requiredScope.toLowerCase();
    final hasWildcard = granted.contains(AgentActionAuthorizationScopes.wildcard.toLowerCase());
    final hasRequired = hasWildcard || granted.contains(normalizedRequired);
    if (!hasRequired) {
      return false;
    }
    return _allowlistPermits(restrictions, actionId.trim());
  }

  static bool _allowlistPermits(ClientTokenRuntimeRestrictions restrictions, String trimmedActionId) {
    if (!restrictions.hasActionIdAllowlist) {
      return true;
    }
    final allowed = restrictions.actionIds;
    if (allowed.isEmpty) {
      return false;
    }
    if (trimmedActionId.isEmpty) {
      return false;
    }
    return allowed.contains(trimmedActionId);
  }
}
