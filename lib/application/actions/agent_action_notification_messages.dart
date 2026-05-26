import 'package:plug_agente/domain/actions/action_enums.dart';

/// User-facing notification bodies for terminal agent action executions.
///
/// Build from `AppLocalizations` via `agentActionNotificationMessages` in
/// `presentation/mappers/agent_action_notification_messages_l10n.dart`.
/// The `english` fallback is used when no locale-specific source is injected.
class AgentActionNotificationMessages {
  const AgentActionNotificationMessages({
    required this.successBody,
    required this.timeoutBody,
    required this.failureFallbackBody,
  });

  final String successBody;
  final String timeoutBody;
  final String failureFallbackBody;

  static const AgentActionNotificationMessages english = AgentActionNotificationMessages(
    successBody: 'Execution finished successfully.',
    timeoutBody: 'Execution exceeded the configured maximum runtime.',
    failureFallbackBody: 'Execution finished with a failure.',
  );

  /// Returns the notification body for [status].
  ///
  /// [failureMessage] is intentionally NOT surfaced in desktop notifications
  /// because it may contain technical details (exit codes, adapter output,
  /// redaction-pending text) that are not safe to display in the OS
  /// notification center. [failureFallbackBody] is always used for failure
  /// states regardless of whether a message is present.
  String? bodyFor({
    required AgentActionExecutionStatus status,
    String? failureMessage,
  }) {
    return switch (status) {
      AgentActionExecutionStatus.succeeded => successBody,
      AgentActionExecutionStatus.timedOut => timeoutBody,
      AgentActionExecutionStatus.failed ||
      AgentActionExecutionStatus.killed ||
      AgentActionExecutionStatus.cancelled ||
      AgentActionExecutionStatus.interrupted ||
      AgentActionExecutionStatus.unknown => failureFallbackBody,
      AgentActionExecutionStatus.skipped => null,
      _ => null,
    };
  }
}
