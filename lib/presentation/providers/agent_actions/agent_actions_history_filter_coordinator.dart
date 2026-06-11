import 'dart:async';

import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';

/// Coordinates history filter mutations and optional period reloads.
final class AgentActionsHistoryFilterCoordinator {
  AgentActionsHistoryFilterCoordinator({
    required AgentActionsHistoryController historyController,
    required AgentActionsExecutionsController executionsController,
    required AgentActionsRemoteAuditController remoteAuditController,
    required void Function() onFiltersChanged,
    required Future<void> Function() reloadExecutionsForPeriod,
  }) : _historyController = historyController,
       _executionsController = executionsController,
       _remoteAuditController = remoteAuditController,
       _onFiltersChanged = onFiltersChanged,
       _reloadExecutionsForPeriod = reloadExecutionsForPeriod;

  final AgentActionsHistoryController _historyController;
  final AgentActionsExecutionsController _executionsController;
  final AgentActionsRemoteAuditController _remoteAuditController;
  final void Function() _onFiltersChanged;
  final Future<void> Function() _reloadExecutionsForPeriod;

  void setStatusFilter(AgentActionExecutionStatus? status) {
    if (!_historyController.updateStatusFilter(status)) {
      return;
    }
    _applyFilterChange(reloadForPeriod: false);
  }

  void setSourceFilter(AgentActionRequestSource? source) {
    if (!_historyController.updateSourceFilter(source)) {
      return;
    }
    _applyFilterChange(reloadForPeriod: false);
  }

  void setPeriodFilter(AgentActionHistoryPeriod period) {
    if (!_historyController.updatePeriodFilter(period)) {
      return;
    }
    _applyFilterChange(reloadForPeriod: true);
  }

  void setFailurePhaseFilter(String? phase) {
    if (!_historyController.updateFailurePhaseFilter(phase)) {
      return;
    }
    _applyFilterChange(reloadForPeriod: false);
  }

  void setSearchQuery(String query) {
    if (!_historyController.updateSearchQuery(query)) {
      return;
    }
    _applyFilterChange(reloadForPeriod: false);
  }

  void clearAllFilters() {
    if (!_historyController.clearAllFilters()) {
      return;
    }
    _applyFilterChange(reloadForPeriod: false);
  }

  void _applyFilterChange({required bool reloadForPeriod}) {
    _remoteAuditController.clearCorrelation();
    _executionsController.invalidateCaches();
    _onFiltersChanged();
    if (reloadForPeriod) {
      unawaited(_reloadExecutionsForPeriod());
    }
  }
}
