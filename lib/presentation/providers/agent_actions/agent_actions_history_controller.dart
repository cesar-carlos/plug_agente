import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_filter_helpers.dart';

enum AgentActionHistoryPeriod {
  all,
  last24Hours,
  last3Days,
}

class AgentActionsHistoryController {
  AgentActionExecutionStatus? statusFilter;
  AgentActionRequestSource? sourceFilter;
  AgentActionHistoryPeriod periodFilter = AgentActionHistoryPeriod.last3Days;
  String? failurePhaseFilter;
  String searchQuery = '';

  bool get hasFilters =>
      statusFilter != null ||
      sourceFilter != null ||
      periodFilter != AgentActionHistoryPeriod.last3Days ||
      failurePhaseFilter != null ||
      searchQuery.isNotEmpty;

  DateTime? periodStart(DateTime Function() now) {
    return switch (periodFilter) {
      AgentActionHistoryPeriod.all => null,
      AgentActionHistoryPeriod.last24Hours => now().subtract(const Duration(hours: 24)),
      AgentActionHistoryPeriod.last3Days => now().subtract(const Duration(days: 3)),
    };
  }

  int executionFetchLimit() => periodFilter == AgentActionHistoryPeriod.all ? 200 : 100;

  bool matchesExecution({
    required AgentActionExecution execution,
    required String selectedActionId,
    required DateTime Function() now,
  }) {
    final periodStartAt = periodStart(now);
    return execution.actionId == selectedActionId &&
        (statusFilter == null || execution.status == statusFilter) &&
        (sourceFilter == null || execution.source == sourceFilter) &&
        (periodStartAt == null || !execution.requestedAt.isBefore(periodStartAt)) &&
        agentActionsMatchesHistoryFailurePhase(
          execution: execution,
          failurePhaseFilter: failurePhaseFilter,
        ) &&
        agentActionsMatchesHistorySearch(
          execution: execution,
          searchQuery: searchQuery,
        );
  }

  void clearFilters() {
    statusFilter = null;
    sourceFilter = null;
    periodFilter = AgentActionHistoryPeriod.last3Days;
    failurePhaseFilter = null;
    searchQuery = '';
  }

  bool updateStatusFilter(AgentActionExecutionStatus? status) {
    if (statusFilter == status) {
      return false;
    }

    statusFilter = status;
    return true;
  }

  bool updateSourceFilter(AgentActionRequestSource? source) {
    if (sourceFilter == source) {
      return false;
    }

    sourceFilter = source;
    return true;
  }

  bool updatePeriodFilter(AgentActionHistoryPeriod period) {
    if (periodFilter == period) {
      return false;
    }

    periodFilter = period;
    return true;
  }

  bool updateFailurePhaseFilter(String? phase) {
    final normalized = phase?.trim();
    final resolved = normalized == null || normalized.isEmpty ? null : normalized;
    if (failurePhaseFilter == resolved) {
      return false;
    }

    failurePhaseFilter = resolved;
    return true;
  }

  bool updateSearchQuery(String query) {
    final normalized = query.trim();
    if (searchQuery == normalized) {
      return false;
    }

    searchQuery = normalized;
    return true;
  }

  bool clearAllFilters() {
    if (!hasFilters) {
      return false;
    }

    clearFilters();
    return true;
  }

  void prepareForRemoteAuditFocus() {
    statusFilter = null;
    sourceFilter = null;
    periodFilter = AgentActionHistoryPeriod.all;
    failurePhaseFilter = null;
    searchQuery = '';
  }

  ({bool didChange, bool periodChanged}) applyRestored({
    required AgentActionExecutionStatus? historyStatus,
    required AgentActionRequestSource? historySource,
    required AgentActionHistoryPeriod historyPeriod,
    required String? historyFailurePhase,
    required String historySearch,
  }) {
    final normalizedHistorySearch = historySearch.trim();
    final normalizedFailurePhase = historyFailurePhase?.trim();
    final resolvedFailurePhase = normalizedFailurePhase == null || normalizedFailurePhase.isEmpty
        ? null
        : normalizedFailurePhase;

    final didChange =
        statusFilter != historyStatus ||
        sourceFilter != historySource ||
        periodFilter != historyPeriod ||
        failurePhaseFilter != resolvedFailurePhase ||
        searchQuery != normalizedHistorySearch;

    if (!didChange) {
      return (didChange: false, periodChanged: false);
    }

    final periodChanged = periodFilter != historyPeriod;
    statusFilter = historyStatus;
    sourceFilter = historySource;
    periodFilter = historyPeriod;
    failurePhaseFilter = resolvedFailurePhase;
    searchQuery = normalizedHistorySearch;
    return (didChange: true, periodChanged: periodChanged);
  }
}
