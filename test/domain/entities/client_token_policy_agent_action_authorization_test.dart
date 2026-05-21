import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy_agent_action_authorization.dart';

void main() {
  group('ClientTokenPolicyAgentActionAuthorization', () {
    test('should treat empty payload as legacy and grant', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: const <String, dynamic>{},
          requiredScope: AgentActionRpcConstants.agentActionsRunScope,
          actionId: 'any',
        ),
      ).isTrue();
    });

    test('should deny when scopes declared but empty', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: <String, dynamic>{
            'agent_actions': <String, dynamic>{
              'scopes': <String>[],
            },
          },
          requiredScope: AgentActionRpcConstants.agentActionsRunScope,
          actionId: 'a1',
        ),
      ).isFalse();
    });

    test('should grant when nested scopes include required scope', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: <String, dynamic>{
            'agent_actions': <String, dynamic>{
              'scopes': <String>[AgentActionRpcConstants.agentActionsRunScope],
            },
          },
          requiredScope: AgentActionRpcConstants.agentActionsRunScope,
          actionId: 'a1',
        ),
      ).isTrue();
    });

    test('should deny allowlist when action_ids is empty list', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: <String, dynamic>{
            'agent_actions': <String, dynamic>{
              'scopes': <String>[AgentActionRpcConstants.agentActionsRunScope],
              'action_ids': <String>[],
            },
          },
          requiredScope: AgentActionRpcConstants.agentActionsRunScope,
          actionId: 'a1',
        ),
      ).isFalse();
    });

    test('should deny allowlist when action_id not listed', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: <String, dynamic>{
            'agent_actions': <String, dynamic>{
              'scopes': <String>[AgentActionRpcConstants.agentActionsRunScope],
              'action_ids': <String>['other'],
            },
          },
          requiredScope: AgentActionRpcConstants.agentActionsRunScope,
          actionId: 'a1',
        ),
      ).isFalse();
    });

    test('should grant when agent_action_scopes lists required scope', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: <String, dynamic>{
            'agent_action_scopes': <String>[AgentActionRpcConstants.agentActionsReadExecutionScope],
          },
          requiredScope: AgentActionRpcConstants.agentActionsReadExecutionScope,
          actionId: 'a1',
        ),
      ).isTrue();
    });

    test('should merge scopes from token_scope string', () {
      check(
        ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
          policyPayload: <String, dynamic>{
            'token_scope': '${AgentActionRpcConstants.agentActionsCancelScope} ${AgentActionRpcConstants.agentActionsRunScope}',
          },
          requiredScope: AgentActionRpcConstants.agentActionsRunScope,
          actionId: 'a1',
        ),
      ).isTrue();
    });
  });
}
