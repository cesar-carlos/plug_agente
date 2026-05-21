import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';

void main() {
  group('AgentActionRpcConstants', () {
    test('published method names should use remote agent action prefix', () {
      for (final name in AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered) {
        expect(name.startsWith(AgentActionRpcConstants.remoteAgentActionMethodPrefix), isTrue);
      }
    });

    test('named method constants should match ordered publish list', () {
      expect(
        [
          AgentActionRpcConstants.agentActionRunRpcMethodName,
          AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          AgentActionRpcConstants.agentActionCancelRpcMethodName,
          AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
        ],
        AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered,
      );
    });

    test('should keep batch-disallowed methods as run and cancel only', () {
      expect(
        AgentActionRpcConstants.jsonRpcBatchDisallowedAgentActionMethodsOrdered,
        [
          AgentActionRpcConstants.agentActionRunRpcMethodName,
          AgentActionRpcConstants.agentActionCancelRpcMethodName,
        ],
      );
    });

    test('should advertise remote agent action limits aligned with default queue caps', () {
      final limits = AgentActionRpcConstants.remoteAgentActionsLimitsCapability;
      final queue = AgentActionRpcConstants.remoteAgentActionsDefaultQueueLimitsCapability;
      expect(limits['maxConcurrentActions'], queue['maxConcurrent']);
      expect(limits['maxQueuedActions'], queue['maxQueued']);
      expect(limits['maxContextBytes'], AgentActionRpcConstants.remoteAgentActionsDefaultMaxContextBytes);
      expect(limits['defaultMaxRuntimeSeconds'], isA<int>());
      expect(limits['defaultMaxRetryAttempts'], isA<int>());
      expect(
        limits['defaultMaxOutputBytesPerStream'],
        AgentActionRpcConstants.defaultMaxOutputBytesPerStream,
      );
      expect(limits['maxMaxOutputBytesPerStream'], AgentActionRpcConstants.maxMaxOutputBytesPerStream);
      expect(
        limits['maxReadMethodsPerBatch'],
        AgentActionPolicyDefaults.maxAgentActionReadRpcMethodsPerBatch,
      );
    });

    test('should resolve max output bytes per stream with default and cap', () {
      expect(AgentActionRpcConstants.resolveMaxOutputBytesPerStream(null), 65536);
      expect(AgentActionRpcConstants.resolveMaxOutputBytesPerStream(4096), 4096);
      expect(AgentActionRpcConstants.resolveMaxOutputBytesPerStream(0), 65536);
      expect(
        AgentActionRpcConstants.resolveMaxOutputBytesPerStream(999999),
        AgentActionRpcConstants.maxMaxOutputBytesPerStream,
      );
    });

    test('should advertise batch policy aligned with batch-disallowed methods', () {
      const policy = AgentActionRpcConstants.remoteAgentActionsBatchPolicyCapability;
      expect(policy[AgentActionRpcConstants.agentActionsBatchPolicyRunKey], isFalse);
      expect(policy[AgentActionRpcConstants.agentActionsBatchPolicyCancelKey], isFalse);
      expect(policy[AgentActionRpcConstants.agentActionsBatchPolicyValidateRunKey], isTrue);
      expect(policy[AgentActionRpcConstants.agentActionsBatchPolicyGetExecutionKey], isTrue);
    });

    test('should keep batch-disallowed methods as a subset of published remote methods', () {
      expect(
        AgentActionRpcConstants.jsonRpcBatchDisallowedAgentActionMethods,
        everyElement(isIn(AgentActionRpcConstants.remotePublishedRpcMethodNames)),
      );
    });

    test('remote RPC methods and OAuth scopes should align in order and count', () {
      expect(
        AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered.length,
        AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered.length,
      );
      expect(
        AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered.toSet().length,
        AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered.length,
      );
      expect(
        AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered.toSet().length,
        AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered.length,
      );
      const expectedPairs = <(String, String)>[
        (
          AgentActionRpcConstants.agentActionRunRpcMethodName,
          AgentActionRpcConstants.agentActionsRunScope,
        ),
        (
          AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          AgentActionRpcConstants.agentActionsValidateRunScope,
        ),
        (
          AgentActionRpcConstants.agentActionCancelRpcMethodName,
          AgentActionRpcConstants.agentActionsCancelScope,
        ),
        (
          AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          AgentActionRpcConstants.agentActionsReadExecutionScope,
        ),
      ];
      for (var i = 0; i < expectedPairs.length; i++) {
        final (String method, String scope) = expectedPairs[i];
        expect(AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered[i], method);
        expect(AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered[i], scope);
      }
    });

    test('wildcard scope should not appear in advertised authorizationScopes list', () {
      expect(
        AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered,
        isNot(contains(AgentActionRpcConstants.agentActionsWildcardScope)),
      );
    });

    test('should keep ordered lists aligned with derived sets', () {
      expect(
        AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered.toSet(),
        AgentActionRpcConstants.remotePublishedRpcMethodNames,
      );
      expect(
        AgentActionRpcConstants.jsonRpcBatchDisallowedAgentActionMethodsOrdered.toSet(),
        AgentActionRpcConstants.jsonRpcBatchDisallowedAgentActionMethods,
      );
    });

    test('batch method-not-allowed technical message should wrap method name', () {
      const method = 'agent.action.run';
      const message =
          '${AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedTechnicalMessagePrefix}'
          '$method'
          '${AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedTechnicalMessageSuffix}';
      expect(message, 'Method agent.action.run is not allowed in JSON-RPC batch');
    });

    test('structured error reasons should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason,
        AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason,
        AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason,
        AgentActionRpcConstants.agentActionPermissionDeniedErrorReason,
        AgentActionRpcConstants.remoteIdempotencyRequiredRpcReason,
        AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason,
        AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedErrorReason,
        AgentActionRpcConstants.jsonRpcBatchAgentActionReadLimitErrorReason,
        AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        AgentActionRpcConstants.agentActionCancelAlreadyFinishedErrorReason,
        AgentActionRpcConstants.agentActionCancelKillFailedErrorReason,
        AgentActionRpcConstants.agentActionCancelResultReasonKilled,
        AgentActionRpcConstants.agentActionCancelResultReasonCancelled,
        AgentActionRpcConstants.agentActionCancelResultReasonCancelRequested,
        AgentActionRpcConstants.agentActionExecutionNotFoundContextReason,
        AgentActionRpcConstants.agentActionCancelNotRunningContextReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
