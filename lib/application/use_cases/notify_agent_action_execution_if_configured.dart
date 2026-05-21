import 'package:plug_agente/application/actions/agent_action_notification_messages.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/domain/actions/actions.dart';

/// Shows a local desktop notification when the action policy requests it.
typedef AgentActionNotificationMessagesResolver = AgentActionNotificationMessages Function();

class NotifyAgentActionExecutionIfConfigured {
  NotifyAgentActionExecutionIfConfigured(
    this._sendNotification, {
    AgentActionNotificationMessagesResolver? resolveMessages,
    bool Function()? notificationsSupported,
  }) : _resolveMessages = resolveMessages ?? _defaultEnglishMessages,
       _notificationsSupported = notificationsSupported;

  final SendNotification _sendNotification;
  final AgentActionNotificationMessagesResolver _resolveMessages;
  final bool Function()? _notificationsSupported;

  static AgentActionNotificationMessages _defaultEnglishMessages() =>
      AgentActionNotificationMessages.english;

  Future<void> call({
    required AgentActionDefinition definition,
    required AgentActionExecution execution,
  }) async {
    if (!(_notificationsSupported?.call() ?? true)) {
      return;
    }

    final policy = definition.policies.notification;
    if (!policy.shouldNotifyFor(execution.status)) {
      return;
    }

    final title = definition.name.trim().isEmpty ? definition.id : definition.name.trim();
    final body = _resolveMessages().bodyFor(
      status: execution.status,
      failureMessage: execution.failureMessage,
    );
    if (body == null) {
      return;
    }

    await _sendNotification(
      title: title,
      body: body,
      payload: 'agent_action:${execution.id}',
    );
  }
}
