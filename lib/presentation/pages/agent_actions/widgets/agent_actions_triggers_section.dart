import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_confirmations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';

class AgentActionTriggersSection extends StatelessWidget {
  const AgentActionTriggersSection({
    required this.provider,
    required this.l10n,
    required this.actionId,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String actionId;

  @override
  Widget build(BuildContext context) {
    final triggerError = provider.triggerErrorMessage;
    if (provider.isLoadingTriggers) {
      return Row(
        children: [
          const SizedBox.square(
            dimension: 16,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              l10n.agentActionsTriggersLoading,
              style: context.bodyMuted,
            ),
          ),
        ],
      );
    }

    final triggersList = provider.triggers.isEmpty
        ? Text(
            l10n.agentActionsTriggersEmpty,
            style: context.bodyMuted,
          )
        : SizedBox(
            height: 220,
            child: ListView.separated(
              itemCount: provider.triggers.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (BuildContext context, int index) {
                final trigger = provider.triggers[index];
                return AgentActionTriggerRow(
                  trigger: trigger,
                  provider: provider,
                  l10n: l10n,
                  actionId: actionId,
                );
              },
            ),
          );

    if (triggerError == null) {
      return triggersList;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBar(
          key: const ValueKey<String>('agent_actions_triggers_section_error'),
          title: Text(l10n.agentActionsErrorTitle),
          content: SelectableText(triggerError),
          severity: InfoBarSeverity.error,
          isLong: true,
          action: Button(
            onPressed: provider.clearTriggerOperationError,
            child: Text(l10n.btnClose),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        triggersList,
      ],
    );
  }
}

class AgentActionTriggerRow extends StatelessWidget {
  const AgentActionTriggerRow({
    required this.trigger,
    required this.provider,
    required this.l10n,
    required this.actionId,
    super.key,
  });

  final AgentActionTrigger trigger;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final String actionId;

  @override
  Widget build(BuildContext context) {
    final title = agentActionTriggerDisplayTitle(trigger, l10n);
    final summary = agentActionTriggerSummaryLine(trigger, l10n);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.bodyStrong),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                trigger.id,
                style: context.bodyMuted,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                summary,
                style: context.bodyMuted,
              ),
            ],
          ),
        ),
        Tooltip(
          message: l10n.agentActionsTriggerEdit,
          child: Semantics(
            button: true,
            label: l10n.agentActionsTriggerEdit,
            child: IconButton(
              key: ValueKey<String>('agent_action_trigger_edit_${trigger.id}'),
              icon: const Icon(FluentIcons.edit),
              onPressed: provider.canManageTriggers && !provider.isSavingTrigger
                  ? () {
                      provider.clearTriggerOperationError();
                      unawaited(
                        showAgentActionTriggerSaveDialog(
                          context: context,
                          provider: provider,
                          l10n: l10n,
                          actionId: actionId,
                          existing: trigger,
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ),
        Tooltip(
          message: l10n.agentActionsTriggerDelete,
          child: Semantics(
            button: true,
            label: l10n.agentActionsTriggerDelete,
            child: IconButton(
              key: ValueKey<String>('agent_action_trigger_delete_${trigger.id}'),
              icon: provider.isDeletingTrigger(trigger.id)
                  ? const SizedBox.square(
                      dimension: 14,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.delete),
              onPressed: provider.isFeatureEnabled && !provider.isDeletingTrigger(trigger.id)
                  ? () {
                      unawaited(
                        confirmAgentActionDeleteTrigger(
                          context,
                          provider,
                          trigger,
                          l10n,
                        ),
                      );
                    }
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
