import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/constants/agent_action_failure_phase_filter_constants.dart';
import 'package:plug_agente/core/theme/theme.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

class AgentActionsHistoryFilters extends StatefulWidget {
  const AgentActionsHistoryFilters({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;

  @override
  State<AgentActionsHistoryFilters> createState() => AgentActionsHistoryFiltersState();
}

class AgentActionsHistoryFiltersState extends State<AgentActionsHistoryFilters> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.provider.historySearchQuery);
  }

  @override
  void didUpdateWidget(covariant AgentActionsHistoryFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.provider.historySearchQuery;
    if (query != _searchController.text) {
      _searchController.text = query;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final l10n = widget.l10n;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionExecutionStatus?>(
            label: l10n.agentActionsHistoryFilterStatus,
            value: provider.historyStatusFilter,
            items: [
              ComboBoxItem<AgentActionExecutionStatus?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionExecutionStatus.values.map(
                (status) => ComboBoxItem<AgentActionExecutionStatus?>(
                  value: status,
                  child: Text(agentActionExecutionStatusLabel(status, l10n)),
                ),
              ),
            ],
            onChanged: (status) {
              provider.setHistoryStatusFilter(status);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historyStatusFilter, status?.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionRequestSource?>(
            label: l10n.agentActionsHistoryFilterSource,
            value: provider.historySourceFilter,
            items: [
              ComboBoxItem<AgentActionRequestSource?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionRequestSource.values.map(
                (source) => ComboBoxItem<AgentActionRequestSource?>(
                  value: source,
                  child: Text(agentActionRequestSourceLabel(source, l10n)),
                ),
              ),
            ],
            onChanged: (source) {
              provider.setHistorySourceFilter(source);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historySourceFilter, source?.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: AppDropdown<AgentActionHistoryPeriod>(
            label: l10n.agentActionsHistoryFilterPeriod,
            value: provider.historyPeriodFilter,
            items: AgentActionHistoryPeriod.values
                .map(
                  (period) => ComboBoxItem<AgentActionHistoryPeriod>(
                    value: period,
                    child: Text(agentActionHistoryPeriodLabel(period, l10n)),
                  ),
                )
                .toList(growable: false),
            onChanged: (period) {
              if (period == null) {
                return;
              }
              provider.setHistoryPeriodFilter(period);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historyPeriodFilter, period.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 210,
          child: AppDropdown<String?>(
            label: l10n.agentActionsHistoryFilterFailurePhase,
            value: provider.historyFailurePhaseFilter,
            items: [
              ComboBoxItem<String?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionFailurePhaseFilterConstants.historyFilterPhases.map(
                (phase) => ComboBoxItem<String?>(
                  value: phase,
                  child: Text(localizeAgentActionFailurePhase(phase, l10n)),
                ),
              ),
            ],
            onChanged: (phase) {
              provider.setHistoryFailurePhaseFilter(phase);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historyFailurePhaseFilter, phase),
              );
            },
          ),
        ),
        SizedBox(
          width: 280,
          child: AppTextField(
            label: l10n.agentActionsHistoryFilterSearch,
            controller: _searchController,
            onChanged: (query) {
              provider.setHistorySearchQuery(query);
              unawaited(widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.historySearch, query.trim()));
            },
            textInputAction: TextInputAction.search,
          ),
        ),
      ],
    );
  }
}
