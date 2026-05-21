import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';

void main() {
  group('AgentActionGateConstants', () {
    test('gate reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionGateConstants.actionNotActiveReason,
        AgentActionGateConstants.featureDisabledReason,
        AgentActionGateConstants.maintenanceModeReason,
        AgentActionGateConstants.remoteFeatureDisabledReason,
        AgentActionGateConstants.remoteAdHocDisabledReason,
        AgentActionGateConstants.elevatedDisabledReason,
        AgentActionGateConstants.elevatedNotConfiguredReason,
        AgentActionGateConstants.elevatedRunnerDegradedReason,
        AgentActionGateConstants.elevatedRequestProtectionFailedReason,
        AgentActionGateConstants.elevatedSubmitFailedReason,
        AgentActionGateConstants.unsupportedForElevatedRunnerReason,
        AgentActionGateConstants.remoteActionNotApprovedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
