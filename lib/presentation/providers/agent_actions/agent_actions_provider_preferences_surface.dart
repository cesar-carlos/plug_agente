part of '../agent_actions_provider.dart';

extension AgentActionsProviderPreferencesSurface on AgentActionsProvider {
  void setHistoryStatusFilter(AgentActionExecutionStatus? status) => _preferencesCoordinator.setStatusFilter(status);

  void setHistorySourceFilter(AgentActionRequestSource? source) => _preferencesCoordinator.setSourceFilter(source);

  void setHistoryPeriodFilter(AgentActionHistoryPeriod period) => _preferencesCoordinator.setPeriodFilter(period);

  void setHistoryFailurePhaseFilter(String? phase) => _preferencesCoordinator.setFailurePhaseFilter(phase);

  void setHistorySearchQuery(String query) => _preferencesCoordinator.setSearchQuery(query);

  void setDefinitionTypeFilter(AgentActionType? type) => _preferencesCoordinator.setDefinitionTypeFilter(type);

  void setDefinitionStateFilter(AgentActionState? state) => _preferencesCoordinator.setDefinitionStateFilter(state);

  void setDefinitionSearchQuery(String query) => _preferencesCoordinator.setDefinitionSearchQuery(query);

  void clearDefinitionFilters() => _preferencesCoordinator.clearDefinitionFilters();

  void applyRestoredPreferences({
    required AgentActionType? definitionType,
    required AgentActionState? definitionState,
    required String definitionSearch,
    required AgentActionExecutionStatus? historyStatus,
    required AgentActionRequestSource? historySource,
    required AgentActionHistoryPeriod historyPeriod,
    required String? historyFailurePhase,
    required String historySearch,
  }) => _preferencesCoordinator.applyRestoredPreferences(
    definitionType: definitionType,
    definitionState: definitionState,
    definitionSearch: definitionSearch,
    historyStatus: historyStatus,
    historySource: historySource,
    historyPeriod: historyPeriod,
    historyFailurePhase: historyFailurePhase,
    historySearch: historySearch,
  );

  void clearHistoryFilters() => _preferencesCoordinator.clearHistoryFilters();
}
