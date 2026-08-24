import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft_kind.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_definition_filters.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_definition_row.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_filter_helpers.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_risk_labels.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_empty_state.dart';
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
      return _AgentActionsEmptyCatalog(
        l10n: l10n,
        canCreate: provider.canSaveAction,
        onCreateAction: onCreateAction,
        isFeatureEnabled: provider.isFeatureEnabled,
      );
    }

    final visibleDefinitions = provider.filteredDefinitions
        .where(
          (definition) => agentActionsMatchesDefinitionListFilter(
            definition: definition,
            typeFilter: provider.definitionTypeFilter,
            stateFilter: provider.definitionStateFilter,
            searchQuery: provider.definitionSearchQuery,
          ),
        )
        .toList(growable: false);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AgentActionsDefinitionFilters(provider: provider, l10n: l10n, uiPreferences: uiPreferences),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: visibleDefinitions.isEmpty
                ? _AgentActionsEmptyFilter(
                    l10n: l10n,
                    onClearFilters: () => clearAgentActionDefinitionListFilters(
                      provider: provider,
                      uiPreferences: uiPreferences,
                    ),
                  )
                : _AgentActionsDefinitionGrid(
                    provider: provider,
                    l10n: l10n,
                    definitions: visibleDefinitions,
                    onShowDetails: onShowDetails,
                    onAddTrigger: onAddTrigger,
                    onEditAction: onEditAction,
                  ),
          ),
        ],
      ),
    );
  }
}

class _AgentActionsEmptyCatalog extends StatelessWidget {
  const _AgentActionsEmptyCatalog({
    required this.l10n,
    required this.canCreate,
    required this.onCreateAction,
    required this.isFeatureEnabled,
  });

  final AppLocalizations l10n;
  final bool canCreate;
  final VoidCallback onCreateAction;
  final bool isFeatureEnabled;

  @override
  Widget build(BuildContext context) {
    Widget createButton = FilledButton(
      onPressed: canCreate ? onCreateAction : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.add),
          const SizedBox(width: AppSpacing.xs),
          Text(l10n.agentActionsFormNew),
        ],
      ),
    );
    if (!canCreate && !isFeatureEnabled) {
      createButton = Tooltip(
        message: l10n.agentActionsDisabledMessage,
        child: createButton,
      );
    }

    return AppCard(
      child: AgentActionsEmptyState(
        message: l10n.agentActionsEmptyActions,
        detail: _AgentActionsSupportedTypesHint(l10n: l10n),
        action: createButton,
      ),
    );
  }
}

class _AgentActionsSupportedTypesHint extends StatelessWidget {
  const _AgentActionsSupportedTypesHint({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final labels = agentActionsSupportedEditorTypeLabels(l10n);
    final muted = context.bodyMuted;

    return Semantics(
      label: agentActionsSupportedEditorTypesHint(l10n),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.xs,
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            Text(labels[index], style: muted),
            if (index < labels.length - 1)
              ExcludeSemantics(
                child: Text('·', style: muted),
              ),
          ],
        ],
      ),
    );
  }
}

class _AgentActionsEmptyFilter extends StatelessWidget {
  const _AgentActionsEmptyFilter({
    required this.l10n,
    required this.onClearFilters,
  });

  final AppLocalizations l10n;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.agentActionsListFilterEmpty,
                style: context.bodyMuted,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.md),
              Button(
                onPressed: onClearFilters,
                child: Text(l10n.ctButtonClearFilters),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveDefinitionSelectionIntent extends Intent {
  const _MoveDefinitionSelectionIntent(this.delta);

  final int delta;
}

class _OpenSelectedDefinitionIntent extends Intent {
  const _OpenSelectedDefinitionIntent();
}

class _AgentActionsDefinitionGrid extends StatefulWidget {
  const _AgentActionsDefinitionGrid({
    required this.provider,
    required this.l10n,
    required this.definitions,
    required this.onShowDetails,
    required this.onAddTrigger,
    required this.onEditAction,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final List<AgentActionDefinition> definitions;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onAddTrigger;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  State<_AgentActionsDefinitionGrid> createState() => _AgentActionsDefinitionGridState();
}

class _AgentActionsDefinitionGridState extends State<_AgentActionsDefinitionGrid> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'agent_actions_definition_grid');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _moveSelection(int delta) {
    final definitions = widget.definitions;
    if (definitions.isEmpty) {
      return;
    }

    final currentId = widget.provider.selectedActionId;
    final currentIndex = definitions.indexWhere((definition) => definition.id == currentId);
    final nextIndex = (currentIndex < 0 ? 0 : currentIndex + delta).clamp(0, definitions.length - 1);
    widget.provider.selectAction(definitions[nextIndex].id);
    _focusNode.requestFocus();
  }

  void _openSelected() {
    final selected = widget.provider.selectedDefinition;
    if (selected == null) {
      return;
    }
    widget.onShowDetails(selected);
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final l10n = widget.l10n;

    return FocusableActionDetector(
      key: const ValueKey<String>('agent_actions_definition_grid'),
      focusNode: _focusNode,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): _MoveDefinitionSelectionIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MoveDefinitionSelectionIntent(-1),
        SingleActivator(LogicalKeyboardKey.enter): _OpenSelectedDefinitionIntent(),
      },
      actions: {
        _MoveDefinitionSelectionIntent: CallbackAction<_MoveDefinitionSelectionIntent>(
          onInvoke: (intent) {
            _moveSelection(intent.delta);
            return null;
          },
        ),
        _OpenSelectedDefinitionIntent: CallbackAction<_OpenSelectedDefinitionIntent>(
          onInvoke: (intent) {
            _openSelected();
            return null;
          },
        ),
      },
      child: AppDataGridScrollable<AgentActionDefinition>(
        columns: [
          AppGridColumn(label: l10n.agentActionsFormName, flex: 4),
          AppGridColumn(label: l10n.agentActionsFormType, flex: 2),
          AppGridColumn(label: l10n.agentActionsFormState, flex: 2),
          AppGridColumn(label: l10n.agentActionsGridColumnRisksTriggers, flex: 2),
          AppGridColumn(label: l10n.ctGridColumnActions, flex: 5, alignment: Alignment.centerRight),
        ],
        rows: widget.definitions,
        rowHeight: 56,
        rowKey: (definition) => ValueKey<String>('agent_action_definition_row_${definition.id}'),
        isRowSelected: (definition) => provider.selectedDefinition?.id == definition.id,
        onRowPressed: (definition) {
          provider.selectAction(definition.id);
          _focusNode.requestFocus();
        },
        rowCells: (definition) {
          final riskDescriptors = collectAgentActionRiskDescriptors(
            definition: definition,
            l10n: l10n,
            runnerUnavailable: provider.isActionTypeUnavailable(definition.type),
            editorUnsupported: !isAgentActionTypeEditableInUi(definition.type),
            needsValidation: definition.state == AgentActionState.needsValidation,
            secretPlaceholderNames: provider.secretPlaceholderNamesFor(definition),
            triggers: definition.id == provider.selectedActionId
                ? provider.triggers
                : const <AgentActionTrigger>[],
          );
          return [
            AgentActionDefinitionNameCell(definition: definition, l10n: l10n),
            Text(agentActionDefinitionTypeLabel(definition, l10n), overflow: TextOverflow.ellipsis),
            Text(agentActionStateLabel(definition.state, l10n), overflow: TextOverflow.ellipsis),
            if (riskDescriptors.isEmpty)
              Text(
                agentActionDefinitionSubtitle(definition, l10n),
                style: context.captionText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: AgentActionRiskChips(descriptors: riskDescriptors),
                ),
              ),
            AgentActionDefinitionRowActions(
              definition: definition,
              provider: provider,
              l10n: l10n,
              onShowDetails: widget.onShowDetails,
              onAddTrigger: widget.onAddTrigger,
              onEditAction: widget.onEditAction,
            ),
          ];
        },
      ),
    );
  }
}
