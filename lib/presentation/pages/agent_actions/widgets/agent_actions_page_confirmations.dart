import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/app_confirm_dialog.dart';

Future<void> confirmAgentActionDeleteTrigger(
  BuildContext context,
  AgentActionsProvider provider,
  AgentActionTrigger trigger,
  AppLocalizations l10n,
) async {
  final label = agentActionTriggerDeleteConfirmLabel(trigger, l10n);
  final confirmed = await AppConfirmDialog.show(
    context: context,
    title: l10n.agentActionsTriggerDeleteConfirmTitle,
    message: l10n.agentActionsTriggerDeleteConfirmMessage(label),
    confirmLabel: l10n.agentActionsTriggerDeleteConfirm,
    cancelLabel: l10n.agentActionsTriggerDeleteCancel,
  );

  if (confirmed) {
    await provider.deleteTrigger(trigger.id);
  }
}

Future<void> confirmAgentActionDelete(
  BuildContext context,
  AgentActionsProvider provider,
  AgentActionDefinition definition,
  AppLocalizations l10n,
) async {
  final confirmed = await AppConfirmDialog.show(
    context: context,
    title: l10n.agentActionsDeleteConfirmTitle,
    message: l10n.agentActionsDeleteConfirmMessage(definition.name),
    confirmLabel: l10n.agentActionsDeleteConfirm,
    cancelLabel: l10n.agentActionsDeleteCancel,
  );

  if (confirmed) {
    await provider.deleteSelectedAction();
  }
}

Future<void> runAgentActionWithDangerousCommandCheck(
  BuildContext context,
  AgentActionsProvider provider,
  AppLocalizations l10n, {
  AgentActionDefinition? definition,
}) async {
  final target = definition ?? provider.selectedDefinition;
  if (target == null || !provider.canRunDefinition(target)) {
    return;
  }

  provider.selectAction(target.id);
  final assessment = provider.assessDangerousCommandForRun(target);
  if (assessment.isBlocked) {
    provider.reportDangerousCommandBlocked(l10n.agentActionsDangerousCommandBlockedMessage);
    return;
  }

  if (assessment.requiresConfirmation) {
    final match = assessment.match;
    if (match == null) {
      return;
    }

    final confirmed = await confirmDangerousCommandRun(
      context: context,
      l10n: l10n,
      patternId: match.patternId,
      patternDescription: match.description,
    );
    if (!confirmed) {
      return;
    }
  }

  await provider.runSelectedAction(
    dangerousCommandConfirmed: assessment.requiresConfirmation,
  );
}

List<Widget> buildAgentActionDangerousCommandRunGuidance({
  required AgentActionsProvider provider,
  required AgentActionDefinition definition,
  required AppLocalizations l10n,
}) {
  final assessment = provider.assessDangerousCommandForRun(definition);
  if (assessment.policy == AgentActionDangerousCommandRunPolicy.allow) {
    return const <Widget>[];
  }

  final match = assessment.match;
  if (match == null) {
    return const <Widget>[];
  }

  if (assessment.isBlocked) {
    return <Widget>[
      InfoBar(
        key: ValueKey<String>('agent_action_dangerous_command_blocked_${definition.id}'),
        title: Text(l10n.agentActionsDangerousCommandBlockedTitle),
        content: Text(l10n.agentActionsDangerousCommandBlockedMessage),
        severity: InfoBarSeverity.error,
        isLong: true,
      ),
      const SizedBox(height: AppSpacing.sm),
    ];
  }

  return <Widget>[
    InfoBar(
      key: ValueKey<String>('agent_action_dangerous_command_warn_${definition.id}'),
      title: Text(l10n.agentActionsDangerousCommandWarnTitle),
      content: Text(
        l10n.agentActionsDangerousCommandWarnMessage(
          match.patternId,
          match.description,
        ),
      ),
      severity: InfoBarSeverity.warning,
      isLong: true,
    ),
    const SizedBox(height: AppSpacing.sm),
  ];
}
