import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_notification_messages.dart';
import 'package:plug_agente/application/use_cases/notify_agent_action_execution_if_configured.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

class _MockSendNotification extends Mock implements SendNotification {}

void main() {
  late _MockSendNotification sendNotification;
  late NotifyAgentActionExecutionIfConfigured notify;

  setUp(() {
    sendNotification = _MockSendNotification();
    notify = NotifyAgentActionExecutionIfConfigured(
      sendNotification,
      resolveMessages: () => AgentActionNotificationMessages.english,
    );
    when(
      () => sendNotification(
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    ).thenAnswer((_) async => const Success(unit));
  });

  test('should send notification when policy allows success', () async {
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Backup job',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        notification: AgentActionNotificationPolicy(notifyOnSuccess: true),
      ),
    );
    final execution = AgentActionExecution(
      id: 'exec-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      redactionApplied: true,
    );

    await notify(definition: definition, execution: execution);

    verify(
      () => sendNotification(
        title: 'Backup job',
        body: AgentActionNotificationMessages.english.successBody,
        payload: 'agent_action:exec-1',
      ),
    ).called(1);
  });

  test('should not send notification when runtime does not support notifications', () async {
    notify = NotifyAgentActionExecutionIfConfigured(
      sendNotification,
      resolveMessages: () => AgentActionNotificationMessages.english,
      notificationsSupported: () => false,
    );
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Backup job',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        notification: AgentActionNotificationPolicy(notifyOnSuccess: true),
      ),
    );
    final execution = AgentActionExecution(
      id: 'exec-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      redactionApplied: true,
    );

    await notify(definition: definition, execution: execution);

    verifyNever(
      () => sendNotification(
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    );
  });

  test('should not send notification when policy disables terminal status', () async {
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Backup job',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
    final execution = AgentActionExecution(
      id: 'exec-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      redactionApplied: true,
    );

    await notify(definition: definition, execution: execution);

    verifyNever(
      () => sendNotification(
        title: any(named: 'title'),
        body: any(named: 'body'),
        payload: any(named: 'payload'),
      ),
    );
  });

  test('should send failure notification when notifyOnFailure is enabled', () async {
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Backup job',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        notification: AgentActionNotificationPolicy(notifyOnFailure: true),
      ),
    );
    final execution = AgentActionExecution(
      id: 'exec-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.failed,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.localUi,
      redactionApplied: true,
      failureMessage: 'Exit code 2',
    );

    await notify(definition: definition, execution: execution);

    // failureMessage is intentionally NOT surfaced in OS notifications;
    // failureFallbackBody is used regardless (see AgentActionNotificationMessages).
    verify(
      () => sendNotification(
        title: 'Backup job',
        body: 'Execution finished with a failure.',
        payload: 'agent_action:exec-1',
      ),
    ).called(1);
  });
}
