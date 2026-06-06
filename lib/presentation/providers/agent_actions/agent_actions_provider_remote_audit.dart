part of '../agent_actions_provider.dart';

Future<void> loadRemoteAuditDuringLoadFor(AgentActionsProvider provider) async {
  if (provider._featureFlags.enableAgentActionRemoteAudit) {
    final auditResult = await provider._listRecentRemoteAudit();
    auditResult.fold(
      (rows) {
        provider._remoteAuditEntries = rows;
        provider._remoteAuditLoadError = null;
      },
      (failure) {
        provider._remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
        provider._remoteAuditLoadError = provider._messageFor(failure);
      },
    );
  } else {
    provider._remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
    provider._remoteAuditLoadError = null;
  }
}

Future<void> refreshRemoteAuditFor(AgentActionsProvider provider) async {
  if (!provider.isRemoteAuditSectionVisible) {
    return;
  }

  provider._isLoadingRemoteAudit = true;
  provider.notifyListeners();

  final auditResult = await provider._listRecentRemoteAudit();
  auditResult.fold(
    (rows) {
      provider._remoteAuditEntries = rows;
      provider._remoteAuditLoadError = null;
    },
    (failure) {
      provider._remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
      provider._remoteAuditLoadError = provider._messageFor(failure);
    },
  );

  provider._isLoadingRemoteAudit = false;
  provider.notifyListeners();
}

String buildRemoteAuditJsonExportFor(AgentActionsProvider provider) {
  return AgentActionsProvider._remoteAuditExport.buildJson(provider._remoteAuditEntries);
}

Future<AgentActionRemoteAuditFocusResult> focusExecutionFromRemoteAuditFor(
  AgentActionsProvider provider,
  AgentActionRemoteAuditRecord record,
) async {
  if (!provider.isFeatureEnabled) {
    return AgentActionRemoteAuditFocusResult.featureDisabled;
  }

  final actionId = record.actionId?.trim();
  if (actionId == null || actionId.isEmpty) {
    return AgentActionRemoteAuditFocusResult.missingActionId;
  }

  provider._historyController.prepareForRemoteAuditFocus();

  final executionId = record.executionId?.trim();
  final selectionChanged = provider._selectedActionId != actionId;
  provider._selectedActionId = actionId;
  provider._auditCorrelationExecutionId = executionId != null && executionId.isNotEmpty ? executionId : null;

  provider.notifyListeners();
  unawaited(provider._syncTriggersForSelection());
  if (selectionChanged) {
    // Mirror selectAction() behaviour so the secrets panel reflects the
    // newly focused action instead of lingering on the previous selection.
    unawaited(provider._refreshSelectedSecretReport());
  }

  if (executionId == null || executionId.isEmpty) {
    return AgentActionRemoteAuditFocusResult.succeeded;
  }

  final visible = provider.filteredSelectedExecutions
      .where((AgentActionExecution e) => e.id == executionId)
      .toList(growable: false);
  if (visible.isNotEmpty) {
    if (!auditRuntimeMatchesExecutionFor(record, visible.single)) {
      provider._auditCorrelationExecutionId = null;
      provider.notifyListeners();
      return AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch;
    }
    return AgentActionRemoteAuditFocusResult.succeeded;
  }

  final fetched = await provider._getExecution(executionId, hydrateCapturedOutput: false);
  if (fetched.isError()) {
    provider._auditCorrelationExecutionId = null;
    provider.notifyListeners();
    return AgentActionRemoteAuditFocusResult.executionNotResolvable;
  }

  final execution = fetched.getOrThrow();
  if (execution.actionId.trim() != actionId) {
    provider._auditCorrelationExecutionId = null;
    provider.notifyListeners();
    return AgentActionRemoteAuditFocusResult.executionNotResolvable;
  }

  if (!auditRuntimeMatchesExecutionFor(record, execution)) {
    provider._auditCorrelationExecutionId = null;
    provider.notifyListeners();
    return AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch;
  }

  mergeExecutionIntoCacheFor(provider, execution);

  if (!provider.filteredSelectedExecutions.any((AgentActionExecution e) => e.id == executionId)) {
    provider._auditCorrelationExecutionId = null;
    provider.notifyListeners();
    return AgentActionRemoteAuditFocusResult.executionNotResolvable;
  }

  return AgentActionRemoteAuditFocusResult.succeeded;
}

bool auditRuntimeMatchesExecutionFor(
  AgentActionRemoteAuditRecord record,
  AgentActionExecution execution,
) {
  final auditInstance = record.runtimeInstanceId?.trim();
  if (auditInstance == null || auditInstance.isEmpty) {
    return true;
  }
  final executionInstance = execution.runtimeInstanceId?.trim();
  if (executionInstance == null || executionInstance.isEmpty) {
    return true;
  }
  return auditInstance == executionInstance;
}

void mergeExecutionIntoCacheFor(AgentActionsProvider provider, AgentActionExecution execution) {
  final merged = <AgentActionExecution>[
    ...provider._executions.where((AgentActionExecution e) => e.id != execution.id),
    execution,
  ]..sort((AgentActionExecution a, AgentActionExecution b) => b.requestedAt.compareTo(a.requestedAt));
  provider._executions = merged;
  provider._invalidateDerivedCaches();
}
