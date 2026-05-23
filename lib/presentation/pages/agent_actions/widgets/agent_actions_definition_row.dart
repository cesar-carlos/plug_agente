import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_confirmations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

class AgentActionDefinitionNameCell extends StatelessWidget {
  const AgentActionDefinitionNameCell({
    required this.definition,
    required this.l10n,
  });

  final AgentActionDefinition definition;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(agentActionDefinitionIconFor(definition), size: 16),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(definition.name, overflow: TextOverflow.ellipsis),
              Text(definition.id, style: context.captionText, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}

class AgentActionDefinitionRowActions extends StatelessWidget {
  const AgentActionDefinitionRowActions({
    required this.definition,
    required this.provider,
    required this.l10n,
    required this.onShowDetails,
    required this.onAddTrigger,
    required this.onEditAction,
  });

  final AgentActionDefinition definition;
  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onAddTrigger;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: l10n.agentActionsRunSelected,
          child: IconButton(
            icon: provider.isRunning
                ? const SizedBox.square(
                    dimension: 14,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Icon(FluentIcons.play),
            onPressed: provider.canRunDefinition(definition)
                ? () {
                    provider.selectAction(definition.id);
                    unawaited(
                      runAgentActionWithDangerousCommandCheck(
                        context,
                        provider,
                        l10n,
                        definition: definition,
                      ),
                    );
                  }
                : null,
          ),
        ),
        Tooltip(
          message: l10n.agentActionsTestSelected,
          child: IconButton(
            icon: provider.isTesting
                ? const SizedBox.square(
                    dimension: 14,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Icon(FluentIcons.test_beaker),
            onPressed: provider.canTestDefinition(definition)
                ? () {
                    provider.selectAction(definition.id);
                    unawaited(provider.testSelectedAction());
                  }
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        DropDownButton(
          key: ValueKey<String>('agent_action_definition_more_${definition.id}'),
          buttonBuilder: (context, onOpen) => IconButton(
            icon: const Icon(FluentIcons.more),
            onPressed: onOpen,
          ),
          items: [
            MenuFlyoutItem(
              key: ValueKey<String>('agent_action_definition_details_${definition.id}'),
              leading: const Icon(FluentIcons.view),
              text: Text(l10n.ctButtonViewDetails),
              onPressed: () {
                provider.selectAction(definition.id);
                onShowDetails(definition);
              },
            ),
            MenuFlyoutItem(
              key: ValueKey<String>('agent_action_definition_trigger_${definition.id}'),
              leading: const Icon(FluentIcons.add_event),
              text: Text(l10n.agentActionsTriggerAdd),
              onPressed: provider.canManageTriggers && !provider.isSavingTrigger
                  ? () {
                      provider.selectAction(definition.id);
                      onAddTrigger(definition);
                    }
                  : null,
            ),
            MenuFlyoutItem(
              key: ValueKey<String>('agent_action_definition_edit_${definition.id}'),
              leading: const Icon(FluentIcons.edit),
              text: Text(l10n.ctButtonEdit),
              onPressed: isAgentActionTypeEditableInUi(definition.type) ? () => onEditAction(definition) : null,
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.delete),
              text: Text(l10n.agentActionsDeleteSelected),
              onPressed: provider.canDeleteDefinition(definition)
                  ? () {
                      provider.selectAction(definition.id);
                      unawaited(confirmAgentActionDelete(context, provider, definition, l10n));
                    }
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}
