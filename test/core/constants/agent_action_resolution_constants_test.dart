import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_resolution_constants.dart';

void main() {
  group('AgentActionResolutionConstants', () {
    test('resolution context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionResolutionConstants.unsupportedActionTypeReason,
        AgentActionResolutionConstants.unsupportedLocalActionRunnerReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
