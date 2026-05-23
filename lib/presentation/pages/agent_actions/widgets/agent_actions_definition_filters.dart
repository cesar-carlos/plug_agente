import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_actions_ui_preferences.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_presenter_labels.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';
import 'package:plug_agente/shared/widgets/common/layout/app_filter_bar.dart';

class AgentActionsDefinitionFilters extends StatefulWidget {
  const AgentActionsDefinitionFilters({
    required this.provider,
    required this.l10n,
    required this.uiPreferences,
    super.key,
  });

  final AgentActionsProvider provider;
  final AppLocalizations l10n;
  final AgentActionsUiPreferences uiPreferences;

  @override
  State<AgentActionsDefinitionFilters> createState() => AgentActionsDefinitionFiltersState();
}

class AgentActionsDefinitionFiltersState extends State<AgentActionsDefinitionFilters> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.provider.definitionSearchQuery);
  }

  @override
  void didUpdateWidget(covariant AgentActionsDefinitionFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.provider.definitionSearchQuery;
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

    return AppFilterBar(
      children: [
        SizedBox(
          width: 220,
          child: AppDropdown<AgentActionType?>(
            label: l10n.agentActionsListFilterType,
            value: provider.definitionTypeFilter,
            items: [
              ComboBoxItem<AgentActionType?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionType.values.map(
                (type) => ComboBoxItem<AgentActionType?>(
                  value: type,
                  child: Text(agentActionTypeLabel(type, l10n)),
                ),
              ),
            ],
            onChanged: (type) {
              provider.setDefinitionTypeFilter(type);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.definitionTypeFilter, type?.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: AppDropdown<AgentActionState?>(
            label: l10n.agentActionsFormState,
            value: provider.definitionStateFilter,
            items: [
              ComboBoxItem<AgentActionState?>(
                child: Text(l10n.agentActionsHistoryFilterAll),
              ),
              ...AgentActionState.values.map(
                (state) => ComboBoxItem<AgentActionState?>(
                  value: state,
                  child: Text(agentActionStateLabel(state, l10n)),
                ),
              ),
            ],
            onChanged: (state) {
              provider.setDefinitionStateFilter(state);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.definitionStateFilter, state?.name),
              );
            },
          ),
        ),
        SizedBox(
          width: 260,
          child: AppTextField(
            label: l10n.agentActionsListFilterSearch,
            controller: _searchController,
            onChanged: (query) {
              provider.setDefinitionSearchQuery(query);
              unawaited(
                widget.uiPreferences.persistString(AgentActionsUiPreferenceKeys.definitionSearch, query.trim()),
              );
            },
            textInputAction: TextInputAction.search,
          ),
        ),
        Button(
          onPressed: provider.hasDefinitionListFilters
              ? () {
                  provider.clearDefinitionFilters();
                  unawaited(
                    widget.uiPreferences.removeKeys([
                      AgentActionsUiPreferenceKeys.definitionTypeFilter,
                      AgentActionsUiPreferenceKeys.definitionStateFilter,
                      AgentActionsUiPreferenceKeys.definitionSearch,
                    ]),
                  );
                }
              : null,
          child: Text(l10n.ctButtonClearFilters),
        ),
      ],
    );
  }
}
