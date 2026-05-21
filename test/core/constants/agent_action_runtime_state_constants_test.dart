import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';

void main() {
  group('AgentActionRuntimeStateConstants', () {
    test('runtime state reason strings should be non-empty and distinct from each other', () {
      final reasons = <String>[
        AgentActionRuntimeStateConstants.shutdownReason,
        AgentActionRuntimeStateConstants.bootstrapReason,
        AgentActionRuntimeStateConstants.appRootDisposeReason,
        AgentActionRuntimeStateConstants.agentActionsStartingReason,
        AgentActionRuntimeStateConstants.agentActionsDrainingReason,
        AgentActionRuntimeStateConstants.agentActionsDegradedReason,
        AgentActionRuntimeStateConstants.subsystemReadyReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
