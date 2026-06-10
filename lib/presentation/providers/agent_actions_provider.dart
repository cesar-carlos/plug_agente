import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/actions/i_action_command_safety_assessor.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/prepare_elevated_action_runner.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_bundle_transfer_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_runtime_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_secrets_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_triggers_controller.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

export 'agent_actions/agent_actions_history_controller.dart' show AgentActionHistoryPeriod;
export 'agent_actions/agent_actions_runtime_controller.dart' show AgentActionsLoadBootstrap;

class AgentActionsProvider extends ChangeNotifier {
  AgentActionsProvider(
    ListAgentActionDefinitions listDefinitions,
    ListAgentActionExecutions listExecutions,
    this._saveDefinition,
    this._deleteDefinition,
    this._listTriggers,
    this._deleteTrigger,
    this._saveTrigger,
    this._listDeveloperData7Connections,
    this._runAction,
    this._testDefinition,
    this._previewDefinition,
    this._cancelExecution,
    this._getExecution,
    this._sliceCapturedOutput,
    this._listRecentRemoteAudit,
    this._exportBundle,
    this._importBundle,
    FeatureFlags featureFlags,
    this._uuid,
    this._commandSafetyAssessor,
    AgentActionRetentionSettings retentionSettings,
    this._bundleFileGateway, {
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    AgentActionSubsystemCoordinator? subsystemCoordinator,
    ActionExecutionQueue? executionQueue,
    AgentActionSecretAvailabilityChecker? secretAvailabilityChecker,
    SaveAgentActionSecret? saveAgentActionSecret,
    DeleteAgentActionSecret? deleteAgentActionSecret,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    PrepareElevatedActionRunner? prepareElevatedActionRunner,
    GlobalStorageContext? globalStorageContext,
    AgentActionTriggerScheduler? triggerScheduler,
    IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics,
    AgentActionPreflightSettings? preflightSettings,
    DateTime Function()? now,
    AgentActionsHistoryController? historyController,
    AgentActionsDefinitionsController? definitionsController,
    AgentActionsExecutionsController? executionsController,
    AgentActionsTriggersController? triggersController,
    AgentActionsSecretsController? secretsController,
    AgentActionsRemoteAuditController? remoteAuditController,
    AgentActionsBundleTransferController? bundleTransferController,
    AgentActionsRuntimeController? runtimeController,
  }) : _executionQueue = executionQueue,
       _triggerScheduler = triggerScheduler,
       _comObjectInvocationDiagnostics = comObjectInvocationDiagnostics,
       _now = now ?? DateTime.now,
       _historyController = historyController ?? AgentActionsHistoryController() {
    _runtimeController = runtimeController ??
        AgentActionsRuntimeController(
          listDefinitions: listDefinitions,
          listExecutions: listExecutions,
          featureFlags: featureFlags,
          retentionSettings: retentionSettings,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
          preflightSettings: preflightSettings,
          runtimeStateGuard: runtimeStateGuard,
          subsystemCoordinator: subsystemCoordinator,
          elevatedRunnerReadiness: elevatedRunnerReadiness,
          prepareElevatedActionRunner: prepareElevatedActionRunner,
          globalStorageContext: globalStorageContext,
        );
    _definitionsController = definitionsController ??
        AgentActionsDefinitionsController(
          saveDefinition: _saveDefinition,
          deleteDefinition: _deleteDefinition,
          listDeveloperData7Connections: _listDeveloperData7Connections,
          uuid: _uuid,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
          preflightSettings: preflightSettings,
          now: _now,
        );
    _executionsController = executionsController ??
        AgentActionsExecutionsController(
          listExecutions: listExecutions,
          runAction: _runAction,
          testDefinition: _testDefinition,
          previewDefinition: _previewDefinition,
          cancelExecution: _cancelExecution,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _triggersController = triggersController ??
        AgentActionsTriggersController(
          listTriggers: _listTriggers,
          saveTrigger: _saveTrigger,
          deleteTrigger: _deleteTrigger,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _secretsController = secretsController ??
        AgentActionsSecretsController(
          secretAvailabilityChecker: secretAvailabilityChecker ?? const AgentActionSecretAvailabilityChecker(),
          saveAgentActionSecret: saveAgentActionSecret,
          deleteAgentActionSecret: deleteAgentActionSecret,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _remoteAuditController = remoteAuditController ??
        AgentActionsRemoteAuditController(
          listRecentRemoteAudit: _listRecentRemoteAudit,
          getExecution: _getExecution,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _bundleTransferController = bundleTransferController ??
        AgentActionsBundleTransferController(
          exportBundle: _exportBundle,
          importBundle: _importBundle,
          bundleFileGateway: _bundleFileGateway,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
  }

  final SaveAgentActionDefinition _saveDefinition;
  final DeleteAgentActionDefinition _deleteDefinition;
  final ListAgentActionTriggers _listTriggers;
  final DeleteAgentActionTrigger _deleteTrigger;
  final SaveAgentActionTrigger _saveTrigger;
  final ListDeveloperData7Connections _listDeveloperData7Connections;
  final RunAgentActionLocally _runAction;
  final TestAgentActionDefinition _testDefinition;
  final PreviewAgentActionDefinition _previewDefinition;
  final CancelAgentActionExecution _cancelExecution;
  final GetAgentActionExecution _getExecution;
  final SliceAgentActionCapturedOutput _sliceCapturedOutput;
  final ListRecentAgentActionRemoteAudit _listRecentRemoteAudit;
  final ExportAgentActionsBundle _exportBundle;
  final ImportAgentActionsBundle _importBundle;
  final Uuid _uuid;
  final IActionCommandSafetyAssessor _commandSafetyAssessor;
  final IAgentActionsBundleFileGateway _bundleFileGateway;
  final ActionExecutionQueue? _executionQueue;
  final AgentActionTriggerScheduler? _triggerScheduler;
  final IComObjectInvocationDiagnostics? _comObjectInvocationDiagnostics;
  final DateTime Function() _now;

  late final AgentActionsDefinitionsController _definitionsController;
  late final AgentActionsExecutionsController _executionsController;
  late final AgentActionsTriggersController _triggersController;
  late final AgentActionsSecretsController _secretsController;
  late final AgentActionsRemoteAuditController _remoteAuditController;
  late final AgentActionsBundleTransferController _bundleTransferController;
  late final AgentActionsRuntimeController _runtimeController;
  final AgentActionsHistoryController _historyController;

  int _periodReloadGeneration = 0;
  String? _errorMessage;

  List<AgentActionDefinition> get definitions => _definitionsController.definitionsView;
  AgentActionType? get definitionTypeFilter => _definitionsController.definitionTypeFilter;
  AgentActionState? get definitionStateFilter => _definitionsController.definitionStateFilter;
  String get definitionSearchQuery => _definitionsController.definitionSearchQuery;
  List<AgentActionDefinition> get filteredDefinitions => _definitionsController.filteredDefinitions();
  bool get hasDefinitionListFilters => _definitionsController.hasDefinitionListFilters;
  List<AgentActionExecution> get executions => _executionsController.executionsView;
  bool get isLoading => _runtimeController.isLoading;
  bool get isSaving => _definitionsController.isSaving;
  bool get isDeleting => _definitionsController.isDeleting;
  bool get isRunning => _executionsController.isRunning;
  bool get isTesting => _executionsController.isTesting;
  bool get isLoadingDeveloperConnections => _definitionsController.isLoadingDeveloperConnections;
  bool get isLoadingTriggers => _triggersController.isLoadingTriggers;
  bool get isSavingTrigger => _triggersController.isSavingTrigger;
  bool get isTransferringBundle => _bundleTransferController.isTransferring;
  List<AgentActionTrigger> get triggers => _triggersController.triggersView;
  String? get errorMessage =>
      _errorMessage ?? _runtimeController.errorMessage ?? _definitionsController.lastOperationErrorMessage;
  String? get triggerErrorMessage => _triggersController.triggerErrorMessage;
  bool get isFeatureEnabled => _runtimeController.isFeatureEnabled;
  bool get isRemoteAgentActionsEnabled => _runtimeController.isRemoteAgentActionsEnabled;
  bool get isRemoteAdHocAgentActionsEnabled => _runtimeController.isRemoteAdHocAgentActionsEnabled;
  bool get isElevatedAgentActionsEnabled => _runtimeController.isElevatedAgentActionsEnabled;
  bool get isElevatedRunnerConfigured => _runtimeController.isElevatedRunnerConfigured;
  bool get isElevatedRunnerDegraded => _runtimeController.isElevatedRunnerDegraded;
  bool get isPreparingElevatedRunner => _runtimeController.isPreparingElevatedRunner;
  bool get isMaintenanceMode => _runtimeController.isMaintenanceMode;
  bool get isMaintenanceStrictMode => _runtimeController.isMaintenanceStrictMode;
  bool get isDangerousCommandWarnModeEnabled => _runtimeController.isDangerousCommandWarnModeEnabled;
  bool get canManageTriggers => isFeatureEnabled && !isMaintenanceMode;
  bool get canTransferBundle =>
      canManageTriggers && !isLoading && !isTransferringBundle && !isSaving && !isDeleting;
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
  @visibleForTesting
  AgentActionsHistoryController get historyController => _historyController;
  @visibleForTesting
  AgentActionsDefinitionsController get definitionsController => _definitionsController;
  @visibleForTesting
  AgentActionsExecutionsController get executionsController => _executionsController;
  @visibleForTesting
  AgentActionsTriggersController get triggersController => _triggersController;
  @visibleForTesting
  AgentActionsSecretsController get secretsController => _secretsController;
  @visibleForTesting
  AgentActionsRemoteAuditController get remoteAuditController => _remoteAuditController;
  @visibleForTesting
  AgentActionsBundleTransferController get bundleTransferController => _bundleTransferController;
  @visibleForTesting
  AgentActionsRuntimeController get runtimeController => _runtimeController;
  AgentActionSecretAvailabilityReport? get selectedSecretReport => _secretsController.selectedSecretReport;
  Set<String> get selectedSecretPlaceholderNames => _secretsController.selectedSecretPlaceholderNames;
  Set<String> get selectedMissingSecretNames => _secretsController.selectedMissingSecretNames;
  bool get isActionSecretStoreAvailable => _secretsController.isActionSecretStoreAvailable;
  String? get secretOperationErrorMessage => _secretsController.secretOperationErrorMessage;
  bool isActionSecretConfigured(String secretName) => _secretsController.isActionSecretConfigured(secretName);
  bool isSavingActionSecret(String secretName) => _secretsController.isSavingActionSecret(secretName);
  bool isDeletingActionSecret(String secretName) => _secretsController.isDeletingActionSecret(secretName);
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

  bool get canRunSelected {
    final definition = selectedDefinition;
    return definition != null && canRunDefinition(definition);
  }

  bool get canTestSelected {
    final definition = selectedDefinition;
    return definition != null && canTestDefinition(definition);
  }

  bool get canSaveAction => _definitionsController.canSaveAction(isFeatureEnabled: isFeatureEnabled);

  bool canSetDefinitionActive(String? actionId, {required bool draftModified}) =>
      _definitionsController.canSetDefinitionActive(actionId, draftModified: draftModified);

  bool isPreflightValidForDefinition(AgentActionDefinition definition) =>
      _definitionsController.isPreflightValidForDefinition(definition);

  bool isPreflightExpiredForDefinition(AgentActionDefinition definition) =>
      _definitionsController.isPreflightExpiredForDefinition(definition);

  DateTime? preflightExpiresAtForDefinition(AgentActionDefinition definition) =>
      _definitionsController.preflightExpiresAtForDefinition(definition);

  bool get canDeleteSelected {
    final definition = selectedDefinition;
    return definition != null && canDeleteDefinition(definition);
  }

  bool canRunDefinition(AgentActionDefinition definition) {
    return isFeatureEnabled && !isRunning && definition.canRun && _allowsLocalManualOperation(definition.type);
  }

  bool canTestDefinition(AgentActionDefinition definition) {
    return isFeatureEnabled && !isTesting && _allowsLocalManualOperation(definition.type);
  }

  bool canDeleteDefinition(AgentActionDefinition definition) {
    return _definitionsController.canDeleteDefinition(
      definition: definition,
      isFeatureEnabled: isFeatureEnabled,
      hasActiveExecution: _executionsController.hasActiveExecutionForDefinition(definition.id),
    );
  }

  AgentActionDangerousCommandAssessment assessDangerousCommandForRun(AgentActionDefinition definition) {
    if (definition.type != AgentActionType.commandLine) {
      return const AgentActionDangerousCommandAssessment.allow();
    }

    final config = definition.config;
    if (config is! CommandLineActionConfig) {
      return const AgentActionDangerousCommandAssessment.allow();
    }

    return _commandSafetyAssessor.assessForLocalRun(
      command: config.command,
      warnModeEnabled: isDangerousCommandWarnModeEnabled,
    );
  }

  void reportDangerousCommandBlocked(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  int get preflightValidityDays => _definitionsController.preflightValidityDays;

  bool get hasPreflightPersistedOverride => _definitionsController.hasPreflightPersistedOverride;

  Future<void> savePreflightValidityDays(int days) => _runtimeController.savePreflightValidityDays(days);

  Future<void> clearPreflightPersistedOverride() => _runtimeController.clearPreflightPersistedOverride();

  int get executionRetentionDays => _runtimeController.executionRetentionDays;
  int get remoteAuditRetentionDays => _runtimeController.remoteAuditRetentionDays;
  int get capturedOutputRetentionHours => _runtimeController.capturedOutputRetentionHours;
  bool get hasRetentionPersistedOverrides => _runtimeController.hasRetentionPersistedOverrides;

  Future<void> saveRetentionSettings({
    required int executionDays,
    required int remoteAuditDays,
    required int capturedOutputHours,
  }) =>
      _runtimeController.saveRetentionSettings(
        executionDays: executionDays,
        remoteAuditDays: remoteAuditDays,
        capturedOutputHours: capturedOutputHours,
      );

  Future<void> clearRetentionPersistedOverrides() => _runtimeController.clearRetentionPersistedOverrides();

  List<AgentActionExecution> get filteredSelectedExecutions => _executionsController.filteredSelectedExecutions(
    selectedDefinition: selectedDefinition,
    historyController: _historyController,
    now: _now,
  );

  bool hasCancellationInProgress(String executionId) =>
      _executionsController.hasCancellationInProgress(executionId);

  bool isDeletingTrigger(String triggerId) => _triggersController.isDeletingTrigger(triggerId);

  bool canCancelExecution(AgentActionExecution execution) => _executionsController.canCancelExecution(
    execution: execution,
    isFeatureEnabled: isFeatureEnabled,
  );

  int get queuedCount => _executionsController.queuedCount;
  int get runningCount => _executionsController.runningCount;
  int get liveQueuePendingCount => _executionQueue?.queuedCount ?? 0;
  int get liveQueueRunningCount => _executionQueue?.runningCount ?? 0;
  bool get hasLiveQueueActivity => liveQueuePendingCount > 0 || liveQueueRunningCount > 0;
  int get summaryQueuedCount => _executionQueue != null ? liveQueuePendingCount : queuedCount;
  int get summaryRunningCount => _executionQueue != null ? liveQueueRunningCount : runningCount;
  bool isActionTypeUnavailable(AgentActionType type) => _runtimeController.isActionTypeUnavailable(type);
  int get failedCount => _executionsController.failedCount;

  Future<void> load() => _runtimeController.load(
        AgentActionsLoadBootstrap(
          historyController: _historyController,
          definitionsController: _definitionsController,
          executionsController: _executionsController,
          remoteAuditController: _remoteAuditController,
          isPreflightValidForDefinition: isPreflightValidForDefinition,
          syncTriggersForSelection: _syncTriggersForSelection,
          refreshSelectedSecretReport: _refreshSelectedSecretReport,
          now: _now,
        ),
      );

  Future<void> prepareElevatedRunner() => _runtimeController.prepareElevatedRunner();

  Future<void> refreshRemoteAudit() => _remoteAuditController.refresh(sectionVisible: isRemoteAuditSectionVisible);

  String buildRemoteAuditJsonExport() => _remoteAuditController.buildJsonExport();

  Future<AgentActionRemoteAuditFocusResult> focusExecutionFromRemoteAudit(
    AgentActionRemoteAuditRecord record,
  ) => _remoteAuditController.focusExecution(
    record: record,
    isFeatureEnabled: isFeatureEnabled,
    definitionsController: _definitionsController,
    executionsController: _executionsController,
    historyController: _historyController,
    now: _now,
    syncTriggers: _syncTriggersForSelection,
    refreshSecrets: _refreshSelectedSecretReport,
  );

  @override
  void notifyListeners() {
    _invalidateDerivedCaches();
    super.notifyListeners();
  }

  void _invalidateDerivedCaches() {
    _definitionsController.invalidateCaches();
    _executionsController.invalidateCaches();
    _triggersController.invalidateCaches();
    _remoteAuditController.invalidateCaches();
  }

  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    int? maxBytes,
  }) {
    return _sliceCapturedOutput(
      executionId: executionId,
      stream: stream,
      offsetUtf8: offsetUtf8,
      maxBytes: maxBytes ?? AgentActionRpcConstants.defaultMaxOutputBytesPerStream,
    );
  }

  Future<void> setMaintenanceMode({required bool enabled}) =>
      _runtimeController.setMaintenanceMode(enabled: enabled);

  Future<void> setMaintenanceStrictMode({required bool enabled}) =>
      _runtimeController.setMaintenanceStrictMode(enabled: enabled);

  bool _allowsLocalManualOperation(AgentActionType actionType) =>
      _runtimeController.allowsLocalManualOperation(actionType);

  void setHistoryStatusFilter(AgentActionExecutionStatus? status) {
    if (!_historyController.updateStatusFilter(status)) {
      return;
    }

    _applyHistoryFilterChange(reloadForPeriod: false);
  }

  void setHistorySourceFilter(AgentActionRequestSource? source) {
    if (!_historyController.updateSourceFilter(source)) {
      return;
    }

    _applyHistoryFilterChange(reloadForPeriod: false);
  }

  void setHistoryPeriodFilter(AgentActionHistoryPeriod period) {
    if (!_historyController.updatePeriodFilter(period)) {
      return;
    }

    _applyHistoryFilterChange(reloadForPeriod: true);
  }

  Future<void> _reloadExecutionsForPeriod() async {
    final errorMessage = await _executionsController.reloadForPeriod(
      historyController: _historyController,
      now: _now,
      isLoading: isLoading,
      nextPeriodReloadGeneration: () => ++_periodReloadGeneration,
      isPeriodReloadCurrent: (generation) => generation == _periodReloadGeneration,
    );
    if (errorMessage != null) {
      _errorMessage = errorMessage;
      notifyListeners();
    }
  }

  void setHistoryFailurePhaseFilter(String? phase) {
    if (!_historyController.updateFailurePhaseFilter(phase)) {
      return;
    }

    _applyHistoryFilterChange(reloadForPeriod: false);
  }

  void setHistorySearchQuery(String query) {
    if (!_historyController.updateSearchQuery(query)) {
      return;
    }

    _applyHistoryFilterChange(reloadForPeriod: false);
  }

  void _applyHistoryFilterChange({required bool reloadForPeriod}) {
    _remoteAuditController.clearCorrelation();
    _executionsController.invalidateCaches();
    notifyListeners();
    if (reloadForPeriod) {
      unawaited(_reloadExecutionsForPeriod());
    }
  }

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
    notifyListeners();
  }

  Set<String> secretPlaceholderNamesFor(AgentActionDefinition definition) =>
      AgentActionSecretPlaceholderScanner.collectFromDefinition(definition);

  bool get hasHistoryFilters => _historyController.hasFilters;

  void clearHistoryFilters() {
    if (!_historyController.clearAllFilters()) {
      return;
    }

    _applyHistoryFilterChange(reloadForPeriod: false);
  }

  Future<void> _refreshSelectedSecretReport() =>
      _secretsController.refreshForDefinition(selectedDefinition);

  void clearSecretOperationError() => _secretsController.clearSecretOperationError();

  Future<Result<Unit>> saveActionSecret({
    required String secretName,
    required String secretValue,
  }) => _secretsController.saveActionSecret(
    secretName: secretName,
    secretValue: secretValue,
    selectedDefinition: selectedDefinition,
  );

  Future<Result<Unit>> deleteActionSecret(String secretName) => _secretsController.deleteActionSecret(
    secretName: secretName,
    selectedDefinition: selectedDefinition,
  );

  Future<void> loadDeveloperData7Connections({
    required String actionId,
    required String data7ConfigPath,
    String? selectedConnectionId,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _definitionsController.loadDeveloperData7Connections(
    actionId: actionId,
    data7ConfigPath: data7ConfigPath,
    selectedConnectionId: selectedConnectionId,
    pathPolicy: pathPolicy,
  );

  void clearDeveloperData7Connections({bool notify = true}) =>
      _definitionsController.clearDeveloperData7Connections(notify: notify);

  Future<bool> saveCommandLineAction({
    required String name,
    required String command,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveCommandLineAction(
      name: name,
      command: command,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      encodingPolicy: encodingPolicy,
      capturePolicy: capturePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> saveExecutableAction({
    required String name,
    required String executablePath,
    required List<String> arguments,
    String? actionId,
    String? description,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveExecutableAction(
      name: name,
      executablePath: executablePath,
      arguments: arguments,
      actionId: actionId,
      description: description,
      workingDirectory: workingDirectory,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      encodingPolicy: encodingPolicy,
      capturePolicy: capturePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> saveScriptAction({
    required String name,
    required String scriptPath,
    required List<String> arguments,
    String? actionId,
    String? description,
    String? interpreterPath,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveScriptAction(
      name: name,
      scriptPath: scriptPath,
      arguments: arguments,
      actionId: actionId,
      description: description,
      interpreterPath: interpreterPath,
      workingDirectory: workingDirectory,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      encodingPolicy: encodingPolicy,
      capturePolicy: capturePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> saveJarAction({
    required String name,
    required String jarPath,
    required List<String> arguments,
    String? actionId,
    String? description,
    String? javaExecutablePath,
    String? workingDirectory,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveJarAction(
      name: name,
      jarPath: jarPath,
      arguments: arguments,
      actionId: actionId,
      description: description,
      javaExecutablePath: javaExecutablePath,
      workingDirectory: workingDirectory,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      encodingPolicy: encodingPolicy,
      capturePolicy: capturePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> saveEmailAction({
    required String name,
    required String smtpProfileId,
    required String from,
    required List<String> to,
    required String subjectTemplate,
    required String bodyTemplate,
    String? actionId,
    String? description,
    List<String> cc = const <String>[],
    List<String> bcc = const <String>[],
    List<AgentActionPathReference> attachmentPaths = const <AgentActionPathReference>[],
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveEmailAction(
      name: name,
      smtpProfileId: smtpProfileId,
      from: from,
      to: to,
      subjectTemplate: subjectTemplate,
      bodyTemplate: bodyTemplate,
      actionId: actionId,
      description: description,
      cc: cc,
      bcc: bcc,
      attachmentPaths: attachmentPaths,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> saveComObjectAction({
    required String name,
    required String progId,
    required String memberName,
    required Map<String, Object?> arguments,
    String? actionId,
    String? description,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveComObjectAction(
      name: name,
      progId: progId,
      memberName: memberName,
      arguments: arguments,
      actionId: actionId,
      description: description,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> saveDeveloperData7Action({
    required String name,
    required String executorPath,
    required String projectPath,
    required String connectionId,
    required String connectionLabel,
    String? actionId,
    String? description,
    String? data7ConfigPath,
    AgentActionState state = AgentActionState.needsValidation,
    AgentActionNotificationPolicy notificationPolicy = const AgentActionNotificationPolicy(),
    AgentActionRetryPolicy retryPolicy = const AgentActionRetryPolicy(),
    AgentActionTimeoutPolicy timeoutPolicy = const AgentActionTimeoutPolicy(),
    AgentActionEnvironmentPolicy environmentPolicy = const AgentActionEnvironmentPolicy(),
    AgentActionExitCodePolicy exitCodePolicy = const AgentActionExitCodePolicy(),
    AgentActionProcessPolicy processPolicy = const AgentActionProcessPolicy(),
    AgentActionLifecyclePolicy lifecyclePolicy = const AgentActionLifecyclePolicy(),
    AgentActionRemotePolicy remotePolicy = const AgentActionRemotePolicy(),
    AgentActionElevatedPolicy elevatedPolicy = const AgentActionElevatedPolicy(),
    AgentActionContextPolicy? contextPolicy,
    AgentActionPathChangePolicy? pathChangePolicy,
    AgentActionEncodingPolicy encodingPolicy = const AgentActionEncodingPolicy(),
    AgentActionCapturePolicy capturePolicy = const AgentActionCapturePolicy(),
    AgentActionQueuePolicy queuePolicy = const AgentActionQueuePolicy(),
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) => _saveWithReload(
    () => _definitionsController.saveDeveloperData7Action(
      name: name,
      executorPath: executorPath,
      projectPath: projectPath,
      connectionId: connectionId,
      connectionLabel: connectionLabel,
      actionId: actionId,
      description: description,
      data7ConfigPath: data7ConfigPath,
      state: state,
      notificationPolicy: notificationPolicy,
      retryPolicy: retryPolicy,
      timeoutPolicy: timeoutPolicy,
      environmentPolicy: environmentPolicy,
      exitCodePolicy: exitCodePolicy,
      processPolicy: processPolicy,
      lifecyclePolicy: lifecyclePolicy,
      remotePolicy: remotePolicy,
      elevatedPolicy: elevatedPolicy,
      contextPolicy: contextPolicy,
      pathChangePolicy: pathChangePolicy,
      encodingPolicy: encodingPolicy,
      capturePolicy: capturePolicy,
      queuePolicy: queuePolicy,
      pathPolicy: pathPolicy,
      canSave: canSaveAction,
    ),
  );

  Future<bool> _saveWithReload(Future<bool> Function() save) async {
    _errorMessage = null;
    _definitionsController.lastOperationErrorMessage = null;
    _executionsController.clearTestStateForSelectionChange();
    final shouldReload = await save();
    if (shouldReload) {
      await load();
      return true;
    }
    return false;
  }

  Future<bool> exportBundleToFile(String filePath, {required AppLocalizations l10n}) async {
    _errorMessage = null;
    final outcome = await _bundleTransferController.exportToFile(
      filePath: filePath,
      l10n: l10n,
      canTransfer: canTransferBundle,
    );
    if (outcome.errorMessage != null) {
      _errorMessage = outcome.errorMessage;
      notifyListeners();
    }
    return outcome.succeeded;
  }

  Future<ImportAgentActionsBundleSummary?> importBundleFromFile(String filePath, {required AppLocalizations l10n}) async {
    _errorMessage = null;
    final outcome = await _bundleTransferController.importFromFile(
      filePath: filePath,
      l10n: l10n,
      canTransfer: canTransferBundle,
    );
    if (outcome.errorMessage != null) {
      _errorMessage = outcome.errorMessage;
      notifyListeners();
      return null;
    }

    final summary = outcome.summary;
    if (summary != null) {
      await load();
    }
    return summary;
  }

  Future<void> deleteSelectedAction() async {
    final definition = selectedDefinition;
    if (definition == null || !canDeleteSelected) {
      return;
    }

    _errorMessage = null;
    _executionsController.clearTestStateForSelectionChange();
    final outcome = await _definitionsController.deleteSelectedAction(
      definition: definition,
      canDelete: canDeleteSelected,
    );

    if (outcome.shouldReload) {
      await load();
      return;
    }

    if (outcome.errorMessage != null) {
      _errorMessage = outcome.errorMessage;
      notifyListeners();
    }
  }

  void selectAction(String actionId) {
    if (_definitionsController.selectedActionId == actionId) {
      return;
    }

    _remoteAuditController.clearCorrelation();
    _definitionsController.selectAction(actionId);
    if (_executionsController.lastTestedActionId != actionId) {
      _executionsController.clearTestStateForSelectionChange();
    }
    notifyListeners();
    unawaited(_syncTriggersForSelection());
    unawaited(_refreshSelectedSecretReport());
  }

  Future<void> refreshTriggersForSelection() => _syncTriggersForSelection();

  void clearTriggerOperationError() => _triggersController.clearTriggerOperationError();

  Future<bool> saveTrigger(AgentActionTrigger trigger) async {
    final ok = await _triggersController.saveTrigger(
      trigger: trigger,
      canManageTriggers: canManageTriggers,
    );
    if (ok) {
      await _syncTriggersForSelection();
    }
    return ok;
  }

  Future<void> deleteTrigger(String triggerId) async {
    await _triggersController.deleteTrigger(
      triggerId: triggerId,
      isFeatureEnabled: isFeatureEnabled,
    );
    await _syncTriggersForSelection();
  }

  Future<void> runSelectedAction({bool dangerousCommandConfirmed = false}) async {
    final definition = selectedDefinition;
    if (definition == null || !canRunSelected) {
      return;
    }

    _errorMessage = null;
    final errorMessage = await _executionsController.runAction(
      definition: definition,
      dangerousCommandConfirmed: dangerousCommandConfirmed,
    );
    if (errorMessage != null) {
      _errorMessage = errorMessage;
      notifyListeners();
      return;
    }

    await load();
  }

  Future<void> testSelectedAction() async {
    final definition = selectedDefinition;
    if (definition == null || !canTestSelected) {
      return;
    }

    _errorMessage = null;
    final outcome = await _executionsController.testAction(
      definition: definition,
      onPreflightSuccess: (testedDefinition) async {
        final errorMessage = await _definitionsController.recordPreflightSuccess(testedDefinition);
        if (errorMessage != null) {
          _errorMessage = errorMessage;
        }
      },
      onPreflightFailure: _definitionsController.clearPreflightSessionForDefinition,
    );

    if (outcome.errorMessage != null) {
      _errorMessage = outcome.errorMessage;
    }
  }

  Future<void> cancelExecution(AgentActionExecution execution) async {
    if (!canCancelExecution(execution)) {
      return;
    }

    _errorMessage = null;
    final errorMessage = await _executionsController.cancelExecution(execution);
    if (errorMessage != null) {
      _errorMessage = errorMessage;
      notifyListeners();
      return;
    }

    await load();
  }

  String _messageFor(Exception failure) => AgentActionFailureDiagnosticsResolver.userMessage(failure);

  Future<void> _syncTriggersForSelection() => _triggersController.syncForSelection(
    actionId: selectedDefinition?.id,
    selectedActionId: _definitionsController.selectedActionId,
  );
}
