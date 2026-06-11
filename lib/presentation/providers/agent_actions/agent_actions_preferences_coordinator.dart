import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_filter_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';

/// Restores persisted UI preferences and coordinates history filter mutations.
final class AgentActionsPreferencesCoordinator {
  AgentActionsPreferencesCoordinator({
    required AgentActionsHistoryController historyController,
    required AgentActionsDefinitionsController definitionsController,
    required AgentActionsExecutionsController executionsController,
    required AgentActionsRemoteAuditController remoteAuditController,
    required void Function() onPreferencesChanged,
    required Future<void> Function() reloadExecutionsForPeriod,
  }) : _historyController = historyController,
       _definitionsController = definitionsController,
       _executionsController = executionsController,
       _remoteAuditController = remoteAuditController,
       _onPreferencesChanged = onPreferencesChanged,
       _historyFilterCoordinator = AgentActionsHistoryFilterCoordinator(
         historyController: historyController,
         executionsController: executionsController,
         remoteAuditController: remoteAuditController,
         onFiltersChanged: onPreferencesChanged,
         reloadExecutionsForPeriod: reloadExecutionsForPeriod,
       );

  final AgentActionsHistoryController _historyController;
  final AgentActionsDefinitionsController _definitionsController;
  final AgentActionsExecutionsController _executionsController;
  final AgentActionsRemoteAuditController _remoteAuditController;
  final void Function() _onPreferencesChanged;
  final AgentActionsHistoryFilterCoordinator _historyFilterCoordinator;

  void setStatusFilter(AgentActionExecutionStatus? status) => _historyFilterCoordinator.setStatusFilter(status);

  void setSourceFilter(AgentActionRequestSource? source) => _historyFilterCoordinator.setSourceFilter(source);

  void setPeriodFilter(AgentActionHistoryPeriod period) => _historyFilterCoordinator.setPeriodFilter(period);

  void setFailurePhaseFilter(String? phase) => _historyFilterCoordinator.setFailurePhaseFilter(phase);

  void setSearchQuery(String query) => _historyFilterCoordinator.setSearchQuery(query);

  void clearHistoryFilters() => _historyFilterCoordinator.clearAllFilters();

  void setDefinitionTypeFilter(AgentActionType? type) => _definitionsController.setDefinitionTypeFilter(type);

  void setDefinitionStateFilter(AgentActionState? state) => _definitionsController.setDefinitionStateFilter(state);

  void setDefinitionSearchQuery(String query) => _definitionsController.setDefinitionSearchQuery(query);

  void clearDefinitionFilters() => _definitionsController.clearDefinitionFilters();

  void applyRestoredPreferences({
    required AgentActionType? definitionType,
    required AgentActionState? definitionState,
    required String definitionSearch,
    required AgentActionExecutionStatus? historyStatus,
    required AgentActionRequestSource? historySource,
    required AgentActionHistoryPeriod historyPeriod,
    required String? historyFailurePhase,
    required String historySearch,
  }) {
    final historyRestore = _historyController.applyRestored(
      historyStatus: historyStatus,
      historySource: historySource,
      historyPeriod: historyPeriod,
      historyFailurePhase: historyFailurePhase,
      historySearch: historySearch,
    );

    final normalizedDefinitionSearch = definitionSearch.trim();
    final didChange =
        _definitionsController.definitionTypeFilter != definitionType ||
        _definitionsController.definitionStateFilter != definitionState ||
        _definitionsController.definitionSearchQuery != normalizedDefinitionSearch ||
        historyRestore.didChange;

    if (!didChange) {
      return;
    }

    _definitionsController.applyRestoredFilters(
      definitionType: definitionType,
      definitionState: definitionState,
      definitionSearch: definitionSearch,
    );
    _remoteAuditController.clearCorrelation();
    _executionsController.invalidateCaches();
    _onPreferencesChanged();
  }
}
