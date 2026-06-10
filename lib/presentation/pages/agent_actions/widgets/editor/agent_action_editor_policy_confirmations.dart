import 'package:flutter/widgets.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';

abstract final class AgentActionEditorPolicyConfirmations {
  AgentActionEditorPolicyConfirmations._();

  static Future<void> handleRemoteEnabledChanged({
    required BuildContext context,
    required AppLocalizations l10n,
    required AgentActionDefinition? definition,
    required bool enabled,
    required VoidCallback onEnable,
    required VoidCallback onDisable,
  }) async {
    if (enabled) {
      if (!context.mounted) {
        return;
      }
      final needsReapproval = definition?.policies.remote.requiresReapproval ?? false;
      final confirmed = needsReapproval
          ? await confirmReapproveRemoteAgentAction(context: context, l10n: l10n)
          : await confirmEnableRemoteAgentAction(context: context, l10n: l10n);
      if (!confirmed || !context.mounted) {
        return;
      }
      onEnable();
      return;
    }

    onDisable();
  }

  static Future<void> handleRemoteAdHocChanged({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool enabled,
    required VoidCallback onApply,
  }) async {
    if (enabled) {
      if (!context.mounted) {
        return;
      }
      final confirmed = await confirmEnableRemoteAdHocAgentAction(context: context, l10n: l10n);
      if (!confirmed || !context.mounted) {
        return;
      }
    }

    onApply();
  }

  static Future<void> handleRunElevatedChanged({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool enabled,
    required VoidCallback onEnable,
    required VoidCallback onDisable,
  }) async {
    if (!enabled) {
      onDisable();
      return;
    }

    if (!context.mounted) {
      return;
    }

    final confirmed = await confirmEnableElevatedAgentAction(context: context, l10n: l10n);
    if (!confirmed || !context.mounted) {
      return;
    }

    onEnable();
  }
}
