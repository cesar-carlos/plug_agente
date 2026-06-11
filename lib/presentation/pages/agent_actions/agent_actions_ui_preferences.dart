import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

/// Stable key for each tab in the Agent Actions page.
///
/// Using a named key instead of a raw index prevents a persisted index from
/// landing on the wrong tab when the tab list changes (e.g. when
/// the remote audit section visibility toggles).
enum AgentActionsTab { actions, history, settings, remoteAudit }

/// Keys for persisting Agent Actions UI filters and tab selection in [IAppSettingsStore].
abstract final class AgentActionsUiPreferenceKeys {
  static const String selectedTab = 'agent_actions.ui.selected_tab';
  static const String definitionTypeFilter = 'agent_actions.ui.definition_type_filter';
  static const String definitionStateFilter = 'agent_actions.ui.definition_state_filter';
  static const String definitionSearch = 'agent_actions.ui.definition_search';
  static const String historyStatusFilter = 'agent_actions.ui.history_status_filter';
  static const String historySourceFilter = 'agent_actions.ui.history_source_filter';
  static const String historyPeriodFilter = 'agent_actions.ui.history_period_filter';
  static const String historyFailurePhaseFilter = 'agent_actions.ui.history_failure_phase_filter';
  static const String historySearch = 'agent_actions.ui.history_search';
}

/// Restores and persists Agent Actions list/history UI preferences.
class AgentActionsUiPreferences {
  AgentActionsUiPreferences(this._resolveStore);

  final IAppSettingsStore? Function() _resolveStore;

  IAppSettingsStore? get _store => _resolveStore();

  AgentActionsTab readSelectedTab() {
    final raw = _store?.getString(AgentActionsUiPreferenceKeys.selectedTab);
    return _enumByName(AgentActionsTab.values, raw) ?? AgentActionsTab.actions;
  }

  Future<void> persistSelectedTab(AgentActionsTab tab) async {
    final store = _store;
    if (store == null) {
      return;
    }
    await store.setString(AgentActionsUiPreferenceKeys.selectedTab, tab.name);
  }

  void restoreInto(AgentActionsProvider provider) {
    final store = _store;
    if (store == null) {
      return;
    }

    provider.applyRestoredPreferences(
      definitionType: _enumByName(
        AgentActionType.values,
        store.getString(AgentActionsUiPreferenceKeys.definitionTypeFilter),
      ),
      definitionState: _enumByName(
        AgentActionState.values,
        store.getString(AgentActionsUiPreferenceKeys.definitionStateFilter),
      ),
      definitionSearch: store.getString(AgentActionsUiPreferenceKeys.definitionSearch) ?? '',
      historyStatus: _enumByName(
        AgentActionExecutionStatus.values,
        store.getString(AgentActionsUiPreferenceKeys.historyStatusFilter),
      ),
      historySource: _enumByName(
        AgentActionRequestSource.values,
        store.getString(AgentActionsUiPreferenceKeys.historySourceFilter),
      ),
      historyPeriod:
          _enumByName(
            AgentActionHistoryPeriod.values,
            store.getString(AgentActionsUiPreferenceKeys.historyPeriodFilter),
          ) ??
          AgentActionHistoryPeriod.last3Days,
      historyFailurePhase: store.getString(AgentActionsUiPreferenceKeys.historyFailurePhaseFilter),
      historySearch: store.getString(AgentActionsUiPreferenceKeys.historySearch) ?? '',
    );
  }

  Future<void> persistString(String key, String? value) async {
    final store = _store;
    if (store == null) {
      return;
    }
    if (value == null || value.isEmpty) {
      await store.remove(key);
      return;
    }
    await store.setString(key, value);
  }

  Future<void> removeKeys(List<String> keys) async {
    final store = _store;
    if (store == null) {
      return;
    }
    for (final key in keys) {
      await store.remove(key);
    }
  }
}

T? _enumByName<T extends Enum>(List<T> values, String? name) {
  if (name == null || name.isEmpty) {
    return null;
  }
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return null;
}
