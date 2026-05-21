import 'dart:ui';

import 'package:plug_agente/application/actions/agent_action_notification_messages.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

/// Resolves notification copy for the current platform locale.
AgentActionNotificationMessages agentActionNotificationMessagesForPlatformLocale() {
  try {
    final l10n = lookupAppLocalizations(PlatformDispatcher.instance.locale);
    return AgentActionNotificationMessages(
      successBody: l10n.agentActionNotificationSuccessBody,
      timeoutBody: l10n.agentActionNotificationTimeoutBody,
      failureFallbackBody: l10n.agentActionNotificationFailureFallbackBody,
    );
  } on Object {
    return AgentActionNotificationMessages.english;
  }
}
