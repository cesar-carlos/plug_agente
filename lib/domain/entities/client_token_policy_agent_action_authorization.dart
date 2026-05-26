import 'package:plug_agente/domain/entities/agent_action_authorization_scopes.dart';

/// Interprets hub-issued `ClientTokenPolicy.payload` for remote `agent.action.*`
/// when `enableClientTokenAuthorization` is on, per `socket_communication_standard.md`.
abstract final class ClientTokenPolicyAgentActionAuthorization {
  /// When false, scope/allowlist checks are skipped (legacy tokens without agent-action metadata).
  static bool payloadDeclaresAgentActionScopeMetadata(Map<String, dynamic> payload) {
    if (payload.containsKey('token_scope')) {
      return true;
    }
    if (payload.containsKey('agent_action_scopes')) {
      return true;
    }
    final nested = payload['agent_actions'];
    if (nested is Map) {
      return nested.containsKey('scopes') || nested.containsKey('action_ids');
    }
    return false;
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
    final granted = _collectGrantedScopes(policyPayload);
    if (granted.isEmpty) {
      return false;
    }
    final normalizedRequired = requiredScope.toLowerCase();
    final hasWildcard = granted.contains(AgentActionAuthorizationScopes.wildcard.toLowerCase());
    final hasRequired = hasWildcard || granted.contains(normalizedRequired);
    if (!hasRequired) {
      return false;
    }
    return _allowlistPermits(policyPayload, actionId.trim());
  }

  static bool _allowlistPermits(Map<String, dynamic> policyPayload, String trimmedActionId) {
    final nested = policyPayload['agent_actions'];
    if (nested is! Map) {
      return true;
    }
    final map = Map<String, dynamic>.from(nested);
    if (!map.containsKey('action_ids')) {
      return true;
    }
    final allowed = _parseStringSet(map['action_ids']);
    if (allowed.isEmpty) {
      return false;
    }
    if (trimmedActionId.isEmpty) {
      return false;
    }
    return allowed.contains(trimmedActionId);
  }

  static Set<String> _collectGrantedScopes(Map<String, dynamic> policyPayload) {
    final out = <String>{};
    _addScopes(out, policyPayload['token_scope']);
    _addScopes(out, policyPayload['agent_action_scopes']);
    final nested = policyPayload['agent_actions'];
    if (nested is Map) {
      final map = Map<String, dynamic>.from(nested);
      _addScopes(out, map['scopes']);
    }
    return out.map((String s) => s.toLowerCase()).toSet();
  }

  static void _addScopes(Set<String> target, Object? raw) {
    if (raw == null) {
      return;
    }
    if (raw is String) {
      for (final part in raw.split(RegExp(r'[\s,]+'))) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) {
          target.add(trimmed);
        }
      }
      return;
    }
    if (raw is Iterable) {
      for (final Object? e in raw) {
        if (e is String) {
          final trimmed = e.trim();
          if (trimmed.isNotEmpty) {
            target.add(trimmed);
          }
        }
      }
    }
  }

  static Set<String> _parseStringSet(Object? raw) {
    if (raw is Iterable) {
      return raw.whereType<String>().map((String s) => s.trim()).where((String s) => s.isNotEmpty).toSet();
    }
    return <String>{};
  }
}
