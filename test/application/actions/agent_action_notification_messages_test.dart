import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_notification_messages.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';

void main() {
  group('AgentActionNotificationMessages', () {
    const messages = AgentActionNotificationMessages.english;

    test('should return success body for succeeded status', () {
      expect(
        messages.bodyFor(status: AgentActionExecutionStatus.succeeded),
        messages.successBody,
      );
    });

    test('should prefer failure message when present', () {
      expect(
        messages.bodyFor(
          status: AgentActionExecutionStatus.failed,
          failureMessage: ' Exit code 2 ',
        ),
        'Exit code 2',
      );
    });

    test('should return null for non-terminal statuses', () {
      expect(
        messages.bodyFor(status: AgentActionExecutionStatus.running),
        isNull,
      );
    });
  });
}
