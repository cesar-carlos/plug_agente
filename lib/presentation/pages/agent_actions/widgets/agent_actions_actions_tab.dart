import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_list.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_dialog.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_toolbar_card.dart';

class AgentActionsActionsTab extends StatelessWidget {
  const AgentActionsActionsTab({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    required this.onCreateAction,
    required this.onShowDetails,
    required this.onEditAction,
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
        AgentActionsToolbarCard(
          provider: provider,
          l10n: l10n,
          onCreateAction: provider.canSaveAction ? onCreateAction : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: AgentActionsList(
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
          ),
        ),
      ],
    );
  }
}
