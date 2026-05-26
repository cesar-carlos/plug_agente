import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_definition_filters.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_definition_row.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_data_grid.dart';

class AgentActionsList extends StatelessWidget {
  const AgentActionsList({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    required this.onCreateAction,
    required this.onShowDetails,
    required this.onAddTrigger,
    required this.onEditAction,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;
  final VoidCallback onCreateAction;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onAddTrigger;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const Center(child: ProgressRing());
    }
    if (provider.definitions.isEmpty) {
      return AppCard(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.processing,
                  size: 36,
                  color: FluentTheme.of(context).accentColor,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l10n.agentActionsEmptyActions,
                  style: context.sectionTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${agentActionTypeLabel(AgentActionType.commandLine, l10n)}, '
                  '${agentActionTypeLabel(AgentActionType.executable, l10n)}, '
                  '${agentActionTypeLabel(AgentActionType.script, l10n)}',
                  style: context.bodyMuted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: provider.canSaveAction ? onCreateAction : null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(FluentIcons.add),
                      const SizedBox(width: AppSpacing.xs),
                      Text(l10n.agentActionsFormNew),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final visibleDefinitions = provider.filteredDefinitions;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentActionsDefinitionFilters(provider: provider, l10n: l10n, uiPreferences: uiPreferences),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AppDataGridScrollable<AgentActionDefinition>(
              columns: [
                AppGridColumn(label: l10n.agentActionsFormName, flex: 4),
                AppGridColumn(label: l10n.agentActionsFormType, flex: 2),
                AppGridColumn(label: l10n.agentActionsFormState, flex: 2),
                AppGridColumn(label: l10n.agentActionsGridColumnRisksTriggers, flex: 2),
                AppGridColumn(label: l10n.ctGridColumnActions, flex: 5, alignment: Alignment.centerRight),
              ],
              rows: visibleDefinitions,
              rowHeight: 52,
              emptyMessage: l10n.agentActionsListFilterEmpty,
              rowKey: (definition) => ValueKey<String>('agent_action_definition_row_${definition.id}'),
              isRowSelected: (definition) => provider.selectedDefinition?.id == definition.id,
              onRowPressed: (definition) => provider.selectAction(definition.id),
              rowCells: (definition) {
                final riskDescriptors = collectAgentActionRiskDescriptors(
                  definition: definition,
                  l10n: l10n,
                  runnerUnavailable: provider.isActionTypeUnavailable(definition.type),
                  editorUnsupported: !isAgentActionTypeEditableInUi(definition.type),
                  needsValidation: definition.state == AgentActionState.needsValidation,
                  secretPlaceholderNames: definition.id == provider.selectedActionId
                      ? provider.selectedSecretPlaceholderNames
                      : provider.secretPlaceholderNamesFor(definition),
                  triggers: definition.id == provider.selectedActionId
                      ? provider.triggers
                      : const <AgentActionTrigger>[],
                );
                return [
                  AgentActionDefinitionNameCell(definition: definition, l10n: l10n),
                  Text(agentActionDefinitionTypeLabel(definition, l10n), overflow: TextOverflow.ellipsis),
                  Text(agentActionStateLabel(definition.state, l10n), overflow: TextOverflow.ellipsis),
                  if (riskDescriptors.isEmpty)
                    Text(agentActionDefinitionSubtitle(definition, l10n), style: context.captionText)
                  else
                    AgentActionRiskChips(descriptors: riskDescriptors),
                  AgentActionDefinitionRowActions(
                    definition: definition,
                    provider: provider,
                    l10n: l10n,
                    onShowDetails: onShowDetails,
                    onAddTrigger: onAddTrigger,
                    onEditAction: onEditAction,
                  ),
                ];
              },
            ),
          ),
        ],
      ),
    );
  }
}
