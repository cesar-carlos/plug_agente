import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_execution_list.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_history_filters.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_actions_page_keys.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_detail_panel.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_card.dart';

class AgentActionsHistoryTab extends StatelessWidget {
  const AgentActionsHistoryTab({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;

  @override
  Widget build(BuildContext context) {
    final selected = provider.selectedDefinition;
    if (selected == null) {
      return AgentActionsEmptySelectionPanel(
        detailScrollKey: AgentActionsPageKeys.detailScroll,
        content: Center(
          child: Text(
            l10n.agentActionsEmptySelection,
            style: context.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(agentActionTypeIcon(selected.type), size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(selected.name, style: context.sectionTitle)),
              if (provider.isLoading)
                const SizedBox.square(
                  dimension: 16,
                  child: ProgressRing(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          IgnorePointer(
            ignoring: provider.isLoading,
            child: AnimatedOpacity(
              opacity: provider.isLoading ? 0.5 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: AgentActionsHistoryFilters(
                provider: provider,
                l10n: l10n,
                uiPreferences: uiPreferences,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: AgentActionExecutionList(
              executions: provider.filteredSelectedExecutions,
              provider: provider,
              l10n: l10n,
            ),
          ),
        ],
      ),
    );
  }
}
