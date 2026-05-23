import 'package:plug_agente/domain/actions/actions.dart';

bool agentActionsMatchesDefinitionListFilter({
  required AgentActionDefinition definition,
  required AgentActionType? typeFilter,
  required AgentActionState? stateFilter,
  required String searchQuery,
}) {
  if (typeFilter != null && definition.type != typeFilter) {
    return false;
  }
  if (stateFilter != null && definition.state != stateFilter) {
    return false;
  }
  if (searchQuery.isEmpty) {
    return true;
  }
  final needle = searchQuery.toLowerCase();
  if (definition.name.toLowerCase().contains(needle)) {
    return true;
  }
  if (definition.id.toLowerCase().contains(needle)) {
    return true;
  }
  return definition.type.name.toLowerCase().contains(needle);
}

bool agentActionsMatchesHistoryFailurePhase({
  required AgentActionExecution execution,
  required String? failurePhaseFilter,
}) {
  final filter = failurePhaseFilter;
  if (filter == null) {
    return true;
  }
  final phase = execution.failurePhase?.trim().toLowerCase();
  return phase != null && phase == filter.toLowerCase();
}

bool agentActionsMatchesHistorySearch({
  required AgentActionExecution execution,
  required String searchQuery,
}) {
  if (searchQuery.isEmpty) {
    return true;
  }

  final needle = searchQuery.toLowerCase();
  if (execution.id.toLowerCase().contains(needle)) {
    return true;
  }

  final idempotencyKey = execution.idempotencyKey?.toLowerCase();
  if (idempotencyKey != null && idempotencyKey.contains(needle)) {
    return true;
  }

  final traceId = execution.traceId?.toLowerCase();
  if (traceId != null && traceId.contains(needle)) {
    return true;
  }

  return false;
}
