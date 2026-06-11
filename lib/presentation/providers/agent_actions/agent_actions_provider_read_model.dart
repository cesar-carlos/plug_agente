part of '../agent_actions_provider.dart';

extension AgentActionsProviderReadModel on AgentActionsProvider {
  List<AgentActionDefinition> get definitions => _definitionsController.definitionsView;
  List<AgentActionDefinition> get filteredDefinitions => _definitionsController.filteredDefinitions();
  List<AgentActionExecution> get executions => _executionsController.executionsView;
  List<AgentActionTrigger> get triggers => _triggersController.triggersView;
  bool get isLoading => _runtimeController.isLoading;
  bool get isSaving => _definitionsController.isSaving;
  bool get isDeleting => _definitionsController.isDeleting;
  bool get isRunning => _executionsController.isRunning;
  bool get isTesting => _executionsController.isTesting;
  bool get isLoadingDeveloperConnections => _definitionsController.isLoadingDeveloperConnections;
  bool get isLoadingTriggers => _triggersController.isLoadingTriggers;
  bool get isSavingTrigger => _triggersController.isSavingTrigger;
  bool get isTransferringBundle => _bundleTransferController.isTransferring;
  AgentActionType? get definitionTypeFilter => _definitionsController.definitionTypeFilter;
  AgentActionState? get definitionStateFilter => _definitionsController.definitionStateFilter;
  String get definitionSearchQuery => _definitionsController.definitionSearchQuery;
  bool get hasDefinitionListFilters => _definitionsController.hasDefinitionListFilters;
  String? get errorMessage =>
      _errorMessage ?? _runtimeController.errorMessage ?? _definitionsController.lastOperationErrorMessage;
  String? get triggerErrorMessage => _triggersController.triggerErrorMessage;
  bool get isFeatureEnabled => _runtimeController.isFeatureEnabled;
  bool get isMaintenanceMode => _runtimeController.isMaintenanceMode;
  bool get isMaintenanceStrictMode => _runtimeController.isMaintenanceStrictMode;
  bool get isDangerousCommandWarnModeEnabled => _runtimeController.isDangerousCommandWarnModeEnabled;
  bool get isRemoteAgentActionsEnabled => _runtimeController.isRemoteAgentActionsEnabled;
  bool get isRemoteAdHocAgentActionsEnabled => _runtimeController.isRemoteAdHocAgentActionsEnabled;
  bool get isElevatedAgentActionsEnabled => _runtimeController.isElevatedAgentActionsEnabled;
  bool get isElevatedRunnerConfigured => _runtimeController.isElevatedRunnerConfigured;
  bool get isElevatedRunnerDegraded => _runtimeController.isElevatedRunnerDegraded;
  bool get isPreparingElevatedRunner => _runtimeController.isPreparingElevatedRunner;
  bool get canManageTriggers => isFeatureEnabled && !isMaintenanceMode;
  bool get canTransferBundle => canManageTriggers && !isLoading && !isTransferringBundle && !isSaving && !isDeleting;
  AgentActionRuntimeStateSnapshot get runtimeSubsystemSnapshot => _runtimeController.runtimeSubsystemSnapshot;
  String? get lastTestedActionId => _executionsController.lastTestedActionId;
  bool? get lastTestCanRun => _executionsController.lastTestCanRun;
  String? get lastTestCommandPreview => _executionsController.lastTestCommandPreview;
  String? get lastTestPreviewErrorMessage => _executionsController.lastTestPreviewErrorMessage;
  Map<String, Object?> get lastTestDiagnostics => Map.unmodifiable(_executionsController.lastTestDiagnostics);
  AgentActionExecutionStatus? get historyStatusFilter => _historyController.statusFilter;
  AgentActionRequestSource? get historySourceFilter => _historyController.sourceFilter;
  AgentActionHistoryPeriod get historyPeriodFilter => _historyController.periodFilter;
  String? get historyFailurePhaseFilter => _historyController.failurePhaseFilter;
  String get historySearchQuery => _historyController.searchQuery;
  AgentActionSecretAvailabilityReport? get selectedSecretReport => _secretsController.selectedSecretReport;
  Set<String> get selectedSecretPlaceholderNames => _secretsController.selectedSecretPlaceholderNames;
  Set<String> get selectedMissingSecretNames => _secretsController.selectedMissingSecretNames;
  bool get isActionSecretStoreAvailable => _secretsController.isActionSecretStoreAvailable;
  String? get secretOperationErrorMessage => _secretsController.secretOperationErrorMessage;
  List<DeveloperData7ConnectionOption> get developerConnections => _definitionsController.developerConnectionsView;
  String? get developerConnectionLookupMessage => _definitionsController.developerConnectionLookupMessage;
  String? get resolvedDeveloperData7ConfigPath => _definitionsController.resolvedDeveloperData7ConfigPath;
  bool get usedDefaultDeveloperData7ConfigPath => _definitionsController.usedDefaultDeveloperData7ConfigPath;
  bool get isRemoteAuditSectionVisible => _runtimeController.isRemoteAuditSectionVisible;
  List<AgentActionRemoteAuditRecord> get remoteAuditEntries => _remoteAuditController.entriesView;
  String? get remoteAuditLoadError => _remoteAuditController.loadError;
  bool get isLoadingRemoteAudit => _remoteAuditController.isLoading;
  String? get auditCorrelationExecutionId => _remoteAuditController.auditCorrelationExecutionId;
  String? get selectedActionId => _definitionsController.selectedActionId;

  String? get schedulerOperationalIssueReason {
    if (!isFeatureEnabled) {
      return null;
    }

    final scheduler = _triggerScheduler;
    if (scheduler == null || scheduler.isTemporalSchedulerStarted) {
      return null;
    }

    return scheduler.lastStartIssueReason;
  }

  int? get comObjectHandlersRegisteredCount {
    if (!isFeatureEnabled || isActionTypeUnavailable(AgentActionType.comObject)) {
      return null;
    }

    return _comObjectInvocationDiagnostics?.registeredHandlerCount;
  }

  bool get shouldWarnComObjectHandlersMissing {
    if (!isFeatureEnabled || isActionTypeUnavailable(AgentActionType.comObject)) {
      return false;
    }

    final hasComObjectDefinitions = _definitionsController.definitions.any(
      (definition) => definition.type == AgentActionType.comObject,
    );
    if (!hasComObjectDefinitions) {
      return false;
    }

    final diagnostics = _comObjectInvocationDiagnostics;
    if (diagnostics == null) {
      return false;
    }

    return diagnostics.registeredHandlerCount <= 0;
  }

  AgentActionDefinition? get selectedDefinition => _definitionsController.selectedDefinition;

  bool get canSaveAction => _definitionsController.canSaveAction(isFeatureEnabled: isFeatureEnabled);

  int get preflightValidityDays => _definitionsController.preflightValidityDays;

  bool get hasPreflightPersistedOverride => _definitionsController.hasPreflightPersistedOverride;

  int get executionRetentionDays => _runtimeController.executionRetentionDays;
  int get remoteAuditRetentionDays => _runtimeController.remoteAuditRetentionDays;
  int get capturedOutputRetentionHours => _runtimeController.capturedOutputRetentionHours;
  bool get hasRetentionPersistedOverrides => _runtimeController.hasRetentionPersistedOverrides;

  int get queuedCount => _executionsController.queuedCount;
  int get runningCount => _executionsController.runningCount;
  int get liveQueuePendingCount => _executionQueue?.queuedCount ?? 0;
  int get liveQueueRunningCount => _executionQueue?.runningCount ?? 0;
  bool get hasLiveQueueActivity => liveQueuePendingCount > 0 || liveQueueRunningCount > 0;
  int get summaryQueuedCount => _executionQueue != null ? liveQueuePendingCount : queuedCount;
  int get summaryRunningCount => _executionQueue != null ? liveQueueRunningCount : runningCount;
  int get failedCount => _executionsController.failedCount;

  bool get hasHistoryFilters => _historyController.hasFilters;

  List<AgentActionExecution> get filteredSelectedExecutions => _executionsController.filteredSelectedExecutions(
    selectedDefinition: selectedDefinition,
    historyController: _historyController,
    now: _now,
  );
}
