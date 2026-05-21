import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_queue_constants.dart';

void main() {
  group('AgentActionQueueConstants', () {
    test('queue reason strings should be non-empty and distinct', () {
      final reasons = <String>[
        AgentActionQueueConstants.queuedExecutionNotFoundReason,
        AgentActionQueueConstants.concurrencyLimitReachedReason,
        AgentActionQueueConstants.concurrencyIgnoreReason,
        AgentActionQueueConstants.queueFullReason,
        AgentActionQueueConstants.queueTimeoutReason,
        AgentActionQueueConstants.queueCancelledReason,
      ];
      expect(reasons, everyElement(isNotEmpty));
      expect(reasons.toSet().length, reasons.length);
    });
  });
}
