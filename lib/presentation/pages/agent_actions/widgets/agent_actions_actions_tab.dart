import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_list.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_confirmations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_select_builder.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_toolbar_card.dart';

class AgentActionsActionsTab extends StatelessWidget {
  const AgentActionsActionsTab({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    required this.onCreateAction,
    required this.onShowDetails,
    required this.onEditAction,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;
  final VoidCallback onCreateAction;
  final ValueChanged<AgentActionDefinition> onShowDetails;
  final ValueChanged<AgentActionDefinition> onEditAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AgentActionsSelectBuilder(
          listenable: provider,
          selector: () => _actionsToolbarListenToken(provider),
          builder: _buildToolbar,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: AgentActionsSelectBuilder(
            listenable: provider,
            selector: () => _actionsListListenToken(provider),
            builder: _buildList,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return AgentActionsToolbarCard(
      provider: provider,
      l10n: l10n,
      onCreateAction: provider.canSaveAction ? onCreateAction : null,
      onRunSelected: provider.canRunSelected
          ? () => unawaited(runAgentActionWithDangerousCommandCheck(context, provider, l10n))
          : null,
    );
  }

  Widget _buildList(BuildContext context) {
    return AgentActionsList(
      provider: provider,
      l10n: l10n,
      uiPreferences: uiPreferences,
      onCreateAction: onCreateAction,
      onShowDetails: onShowDetails,
      onAddTrigger: (definition) {
        provider.selectAction(definition.id);
        provider.clearTriggerOperationError();
        unawaited(
          showAgentActionTriggerSaveDialog(
            context: context,
            provider: provider,
            l10n: l10n,
            actionId: definition.id,
          ),
        );
      },
      onEditAction: onEditAction,
    );
  }
}

int _actionsToolbarListenToken(AgentActionsProvider provider) {
  return Object.hashAll([
    provider.isLoading,
    provider.isSaving,
    provider.isDeleting,
    provider.isRunning,
    provider.isTesting,
    provider.isTransferringBundle,
    provider.isMaintenanceMode,
    provider.isMaintenanceStrictMode,
    provider.isFeatureEnabled,
    provider.canSaveAction,
    provider.canRunSelected,
    provider.canTestSelected,
    provider.canTransferBundle,
    provider.hasLiveQueueActivity,
    provider.liveQueuePendingCount,
    provider.liveQueueRunningCount,
  ]);
}

int _actionsListListenToken(AgentActionsProvider provider) {
  final runtime = provider.runtimeSubsystemSnapshot;
  return Object.hashAll([
    provider.isLoading,
    provider.isSaving,
    provider.isDeleting,
    provider.isRunning,
    provider.isTesting,
    provider.isTransferringBundle,
    provider.isFeatureEnabled,
    provider.canSaveAction,
    provider.selectedActionId,
    provider.definitionTypeFilter,
    provider.definitionStateFilter,
    provider.definitionSearchQuery,
    provider.hasDefinitionListFilters,
    identityHashCode(provider.definitions),
    provider.definitions.length,
    provider.isSavingTrigger,
    provider.canManageTriggers,
    identityHashCode(provider.triggers),
    provider.triggers.length,
    runtime.status,
    runtime.unavailableActionTypes.length,
    runtime.reason,
  ]);
}
