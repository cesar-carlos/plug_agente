import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';

void main() {
  group('AgentActionTriggerConstants', () {
    test('trigger context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionTriggerConstants.blankActionIdReason,
        AgentActionTriggerConstants.nonTemporalTriggerReason,
        AgentActionTriggerConstants.triggerDisabledReason,
        AgentActionTriggerConstants.lifecycleTriggerTimeoutReason,
        AgentActionTriggerConstants.appCloseRuntimeTooLongReason,
        AgentActionTriggerConstants.appCloseElevatedActionBlockedReason,
        AgentActionTriggerConstants.appCloseRemoteActionBlockedReason,
        AgentActionTriggerConstants.remoteApprovalAppCloseConflictReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
