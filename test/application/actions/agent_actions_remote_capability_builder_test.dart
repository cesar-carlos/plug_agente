import 'package:plug_agente/application/actions/agent_actions_remote_capability_builder.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:test/test.dart';

void main() {
  group('AgentActionsRemoteCapabilityBuilder', () {
    test('should publish stable extensions.agentActions shape for remote hubs', () {
      final capability = AgentActionsRemoteCapabilityBuilder.build(
        supportedTypes: const <String>['commandLine'],
        status: 'ready',
        maintenanceMode: false,
        maintenanceStrictMode: true,
        unavailableTypes: const <String>[],
        remoteAdHoc: false,
        elevatedAllowed: true,
        supportsElevated: false,
        operationalProfile: 'production',
      );

      expect(capability['enabled'], isTrue);
      expect(capability['maintenanceStrictMode'], isTrue);
      expect(capability['profile'], 'production');
      expect(capability['methods'], AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered);
      expect(capability['supportedTypes'], const <String>['commandLine']);
      expect(capability['requiresIdempotencyKey'], isTrue);
      expect(capability['supportsCancel'], isTrue);
      expect(capability['supportsContext'], isFalse);
      expect(capability['supportsElevated'], isFalse);
      expect(capability['remoteAdHoc'], isFalse);
      expect(capability['batchPolicy'], AgentActionRpcConstants.remoteAgentActionsBatchPolicyCapability);
      expect(capability['limits'], AgentActionRpcConstants.remoteAgentActionsLimitsCapability);
      final limits = capability['limits']! as Map<String, Object?>;
      expect(limits['maxReadMethodsPerBatch'], isA<int>());
      expect(limits['maxReadMethodsPerBatch'], greaterThan(0));
      expect(capability, contains('maxConcurrentActions'));
      expect(capability, contains('maxQueuedActions'));
      expect(capability, contains('defaultQueueLimits'));
    });
  });
}
