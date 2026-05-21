import 'package:plug_agente/application/actions/agent_action_notification_messages.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// Builds notification messages from an explicit [AppLocalizations] (UI/tests).
AgentActionNotificationMessages agentActionNotificationMessages(AppLocalizations l10n) {
  return AgentActionNotificationMessages(
    successBody: l10n.agentActionNotificationSuccessBody,
    timeoutBody: l10n.agentActionNotificationTimeoutBody,
    failureFallbackBody: l10n.agentActionNotificationFailureFallbackBody,
  );
}
