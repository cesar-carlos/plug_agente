import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';

void main() {
  group('AgentActionValidationConstants', () {
    test('validation context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionValidationConstants.fieldRequiredReason,
        AgentActionValidationConstants.blankValueReason,
        AgentActionValidationConstants.blankFilterReason,
        AgentActionValidationConstants.invalidVersionReason,
        AgentActionValidationConstants.invalidQueuePolicyReason,
        AgentActionValidationConstants.invalidTimeoutPolicyReason,
        AgentActionValidationConstants.elevatedRetryNotAllowedReason,
        AgentActionValidationConstants.invalidPathPolicyReason,
        AgentActionValidationConstants.invalidContextJsonSchemaDefinitionReason,
        AgentActionValidationConstants.invalidContextPathReason,
        AgentActionValidationConstants.invalidRuntimeParametersReason,
        AgentActionValidationConstants.invalidIdempotencyKeyReason,
        AgentActionValidationConstants.invalidRequestedByReason,
        AgentActionValidationConstants.invalidTraceIdReason,
        AgentActionValidationConstants.invalidTriggerIdReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
