import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';

void main() {
  group('AgentActionProcessConstants', () {
    test('process context reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionProcessConstants.invalidActionConfigReason,
        AgentActionProcessConstants.processStartFailedReason,
        AgentActionProcessConstants.processRuntimeErrorReason,
        AgentActionProcessConstants.processNotActiveReason,
        AgentActionProcessConstants.pidMismatchReason,
        AgentActionProcessConstants.processIdentityMismatchReason,
        AgentActionProcessConstants.processIdentityUnavailableReason,
        AgentActionProcessConstants.stdinCloseFailedReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
