import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/actions/agent_action_remote_audit_support_export.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
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
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

enum AgentActionHistoryPeriod {
  all,
  last24Hours,
  last3Days,
}

class AgentActionsProvider extends ChangeNotifier {

  AgentActionsProvider(
    this._listDefinitions,
    this._listExecutions,
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
    this._featureFlags,
    this._uuid, {
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
    DateTime Function()? now,
  }) : _runtimeStateGuard = runtimeStateGuard,
       _subsystemCoordinator = subsystemCoordinator,
       _executionQueue = executionQueue,
       _secretAvailabilityChecker = secretAvailabilityChecker ?? const AgentActionSecretAvailabilityChecker(),
       _saveAgentActionSecret = saveAgentActionSecret,
       _deleteAgentActionSecret = deleteAgentActionSecret,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _prepareElevatedActionRunner = prepareElevatedActionRunner,
       _globalStorageContext = globalStorageContext,
       _triggerScheduler = triggerScheduler,
       _comObjectInvocationDiagnostics = comObjectInvocationDiagnostics,
       _now = now ?? DateTime.now;
  static const AgentActionRemoteAuditSupportExport _remoteAuditExport = AgentActionRemoteAuditSupportExport();

  final ListAgentActionDefinitions _listDefinitions;
  final ListAgentActionExecutions _listExecutions;
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
  final FeatureFlags _featureFlags;
  final Uuid _uuid;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final AgentActionSubsystemCoordinator? _subsystemCoordinator;
  final ActionExecutionQueue? _executionQueue;
  final AgentActionSecretAvailabilityChecker _secretAvailabilityChecker;
  final SaveAgentActionSecret? _saveAgentActionSecret;
  final DeleteAgentActionSecret? _deleteAgentActionSecret;
  final ElevatedActionRunnerReadinessService? _elevatedRunnerReadiness;
  final PrepareElevatedActionRunner? _prepareElevatedActionRunner;
  final GlobalStorageContext? _globalStorageContext;
  final AgentActionTriggerScheduler? _triggerScheduler;
  final IComObjectInvocationDiagnostics? _comObjectInvocationDiagnostics;
  final DateTime Function() _now;

  bool _isPreparingElevatedRunner = false;

  List<AgentActionDefinition> _definitions = <AgentActionDefinition>[];
  List<AgentActionExecution> _executions = <AgentActionExecution>[];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isRunning = false;
  bool _isTesting = false;
  bool _isLoadingDeveloperConnections = false;
  bool _isLoadingTriggers = false;
  bool _isSavingTrigger = false;
  bool _isTransferringBundle = false;
  final Set<String> _cancellingExecutionIds = <String>{};
  final Set<String> _deletingTriggerIds = <String>{};
  List<AgentActionTrigger> _triggers = <AgentActionTrigger>[];
  String? _selectedActionId;
  String? _errorMessage;
  String? _lastTestedActionId;
  bool? _lastTestCanRun;
  String? _lastTestCommandPreview;
  String? _lastTestPreviewErrorMessage;
  Map<String, Object?> _lastTestDiagnostics = const <String, Object?>{};
  AgentActionExecutionStatus? _historyStatusFilter;
  AgentActionRequestSource? _historySourceFilter;
  AgentActionHistoryPeriod _historyPeriodFilter = AgentActionHistoryPeriod.all;
  String? _historyFailurePhaseFilter;
  String _historySearchQuery = '';
  AgentActionType? _definitionTypeFilter;
  String _definitionSearchQuery = '';
  AgentActionSecretAvailabilityReport? _selectedSecretReport;
  String? _savingActionSecretName;
  String? _deletingActionSecretName;
  String? _secretOperationErrorMessage;
  List<DeveloperData7ConnectionOption> _developerConnections = <DeveloperData7ConnectionOption>[];
  String? _developerConnectionLookupMessage;
  String? _resolvedDeveloperData7ConfigPath;
  bool _usedDefaultDeveloperData7ConfigPath = false;
  List<AgentActionRemoteAuditRecord> _remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
  String? _remoteAuditLoadError;
  bool _isLoadingRemoteAudit = false;
  String? _auditCorrelationExecutionId;

  List<AgentActionDefinition> get definitions => List.unmodifiable(_definitions);
  AgentActionType? get definitionTypeFilter => _definitionTypeFilter;
  String get definitionSearchQuery => _definitionSearchQuery;

  List<AgentActionDefinition> get filteredDefinitions {
    final matched = _definitions.where(_matchesDefinitionListFilter).toList(growable: false);
    final selectedId = selectedActionId;
    if (selectedId == null) {
      return matched;
    }
    if (matched.any((definition) => definition.id == selectedId)) {
      return matched;
    }
    final selected = _existingDefinition(selectedId);
    if (selected == null) {
      return matched;
    }
    return <AgentActionDefinition>[selected, ...matched];
  }

  bool get hasDefinitionListFilters =>
      _definitionTypeFilter != null || _definitionSearchQuery.isNotEmpty;
  List<AgentActionExecution> get executions => List.unmodifiable(_executions);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isDeleting => _isDeleting;
  bool get isRunning => _isRunning;
  bool get isTesting => _isTesting;
  bool get isLoadingDeveloperConnections => _isLoadingDeveloperConnections;
  bool get isLoadingTriggers => _isLoadingTriggers;
  bool get isSavingTrigger => _isSavingTrigger;
  bool get isTransferringBundle => _isTransferringBundle;
  List<AgentActionTrigger> get triggers => List.unmodifiable(_triggers);
  String? get errorMessage => _errorMessage;
  bool get isFeatureEnabled => _featureFlags.enableAgentActions;
  bool get isRemoteAgentActionsEnabled => _featureFlags.enableRemoteAgentActions;
  bool get isRemoteAdHocAgentActionsEnabled => _featureFlags.enableRemoteAdHocAgentActions;
  bool get isElevatedAgentActionsEnabled => _featureFlags.enableElevatedAgentActions;
  bool get isElevatedRunnerConfigured => _elevatedRunnerReadiness?.isConfigured ?? false;
  bool get isElevatedRunnerDegraded => _elevatedRunnerReadiness?.isDegraded ?? false;
  bool get isPreparingElevatedRunner => _isPreparingElevatedRunner;
  bool get isMaintenanceMode => _featureFlags.enableAgentActionsMaintenanceMode;
  bool get canManageTriggers => isFeatureEnabled && !isMaintenanceMode;
  bool get canTransferBundle =>
      canManageTriggers && !_isLoading && !_isTransferringBundle && !_isSaving && !_isDeleting;
  AgentActionRuntimeStateSnapshot get runtimeSubsystemSnapshot =>
      _runtimeStateGuard?.snapshot ??
      const AgentActionRuntimeStateSnapshot(status: AgentActionSubsystemStatus.ready);
  String? get lastTestedActionId => _lastTestedActionId;
  bool? get lastTestCanRun => _lastTestCanRun;
  String? get lastTestCommandPreview => _lastTestCommandPreview;
  String? get lastTestPreviewErrorMessage => _lastTestPreviewErrorMessage;
  Map<String, Object?> get lastTestDiagnostics => Map.unmodifiable(_lastTestDiagnostics);
  AgentActionExecutionStatus? get historyStatusFilter => _historyStatusFilter;
  AgentActionRequestSource? get historySourceFilter => _historySourceFilter;
  AgentActionHistoryPeriod get historyPeriodFilter => _historyPeriodFilter;
  String? get historyFailurePhaseFilter => _historyFailurePhaseFilter;
  String get historySearchQuery => _historySearchQuery;
  AgentActionSecretAvailabilityReport? get selectedSecretReport => _selectedSecretReport;
  Set<String> get selectedSecretPlaceholderNames =>
      _selectedSecretReport?.referencedSecretNames ?? const <String>{};
  Set<String> get selectedMissingSecretNames => _selectedSecretReport?.missingSecretNames ?? const <String>{};
  bool get isActionSecretStoreAvailable =>
      _saveAgentActionSecret != null && _deleteAgentActionSecret != null;
  String? get secretOperationErrorMessage => _secretOperationErrorMessage;

  bool isActionSecretConfigured(String secretName) {
    final report = _selectedSecretReport;
    if (report == null) {
      return false;
    }
    return report.referencedSecretNames.contains(secretName) &&
        !report.missingSecretNames.contains(secretName);
  }

  bool isSavingActionSecret(String secretName) => _savingActionSecretName == secretName;

  bool isDeletingActionSecret(String secretName) => _deletingActionSecretName == secretName;
  List<DeveloperData7ConnectionOption> get developerConnections => List.unmodifiable(_developerConnections);
  String? get developerConnectionLookupMessage => _developerConnectionLookupMessage;
  String? get resolvedDeveloperData7ConfigPath => _resolvedDeveloperData7ConfigPath;
  bool get usedDefaultDeveloperData7ConfigPath => _usedDefaultDeveloperData7ConfigPath;

  bool get isRemoteAuditSectionVisible => isFeatureEnabled && _featureFlags.enableAgentActionRemoteAudit;

  /// When temporal scheduling did not start, exposes a stable reason for operator messaging.
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

  /// Registered COM handler count when diagnostics are wired; `null` when COM is unavailable or diagnostics omitted.
  int? get comObjectHandlersRegisteredCount {
    if (!isFeatureEnabled || isActionTypeUnavailable(AgentActionType.comObject)) {
      return null;
    }

    return _comObjectInvocationDiagnostics?.registeredHandlerCount;
  }

  /// True when the COM runner is registered but no ProgID/member handlers are configured.
  bool get shouldWarnComObjectHandlersMissing {
    if (!isFeatureEnabled || isActionTypeUnavailable(AgentActionType.comObject)) {
      return false;
    }

    final diagnostics = _comObjectInvocationDiagnostics;
    if (diagnostics == null) {
      return false;
    }

    return diagnostics.registeredHandlerCount <= 0;
  }

  List<AgentActionRemoteAuditRecord> get remoteAuditEntries => List.unmodifiable(_remoteAuditEntries);
  String? get remoteAuditLoadError => _remoteAuditLoadError;
  bool get isLoadingRemoteAudit => _isLoadingRemoteAudit;
  String? get auditCorrelationExecutionId => _auditCorrelationExecutionId;

  String? get selectedActionId => _selectedActionId;

  AgentActionDefinition? get selectedDefinition {
    final selectedId = _selectedActionId;
    if (selectedId == null) {
      return _definitions.firstOrNull;
    }

    return _definitions.where((definition) => definition.id == selectedId).firstOrNull ?? _definitions.firstOrNull;
  }

  bool get canRunSelected {
    final definition = selectedDefinition;
    return isFeatureEnabled &&
        !_isRunning &&
        definition != null &&
        definition.canRun &&
        _allowsLocalManualOperation(definition.type);
  }

  bool get canTestSelected {
    final definition = selectedDefinition;
    return isFeatureEnabled &&
        !_isTesting &&
        definition != null &&
        _allowsLocalManualOperation(definition.type);
  }

  bool get canSaveAction {
    return isFeatureEnabled && !_isSaving;
  }

  bool get canDeleteSelected {
    final definition = selectedDefinition;
    if (!isFeatureEnabled || _isDeleting || definition == null) {
      return false;
    }

    return !_executions.any(
      (execution) => execution.actionId == definition.id && !execution.isTerminal,
    );
  }

  List<AgentActionExecution> get filteredSelectedExecutions {
    final selected = selectedDefinition;
    if (selected == null) {
      return const <AgentActionExecution>[];
    }

    final periodStart = _historyPeriodStart();
    final filtered = _executions
        .where((execution) {
          final matchesAction = execution.actionId == selected.id;
          final matchesStatus = _historyStatusFilter == null || execution.status == _historyStatusFilter;
          final matchesSource = _historySourceFilter == null || execution.source == _historySourceFilter;
          final matchesPeriod = periodStart == null || !execution.requestedAt.isBefore(periodStart);
          final matchesFailurePhase = _matchesHistoryFailurePhase(execution);
          final matchesSearch = _matchesHistorySearch(execution);
          return matchesAction &&
              matchesStatus &&
              matchesSource &&
              matchesPeriod &&
              matchesFailurePhase &&
              matchesSearch;
        })
        .toList(growable: false);

    filtered.sort((left, right) => right.requestedAt.compareTo(left.requestedAt));
    return filtered;
  }

  bool hasCancellationInProgress(String executionId) {
    return _cancellingExecutionIds.contains(executionId);
  }

  bool isDeletingTrigger(String triggerId) {
    return _deletingTriggerIds.contains(triggerId);
  }

  bool canCancelExecution(AgentActionExecution execution) {
    return isFeatureEnabled &&
        !execution.isTerminal &&
        !hasCancellationInProgress(execution.id) &&
        (execution.status == AgentActionExecutionStatus.queued ||
            execution.status == AgentActionExecutionStatus.running);
  }

  int get queuedCount {
    return _executions.where((execution) => execution.status == AgentActionExecutionStatus.queued).length;
  }

  int get runningCount {
    return _executions.where((execution) => execution.status == AgentActionExecutionStatus.running).length;
  }

  int get liveQueuePendingCount => _executionQueue?.queuedCount ?? 0;

  int get liveQueueRunningCount => _executionQueue?.runningCount ?? 0;

  bool get hasLiveQueueActivity => liveQueuePendingCount > 0 || liveQueueRunningCount > 0;

  int get summaryQueuedCount => _executionQueue != null ? liveQueuePendingCount : queuedCount;

  int get summaryRunningCount => _executionQueue != null ? liveQueueRunningCount : runningCount;

  bool isActionTypeUnavailable(AgentActionType type) => runtimeSubsystemSnapshot.blocksType(type);

  int get failedCount {
    return _executions.where((execution) => execution.status == AgentActionExecutionStatus.failed).length;
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    _auditCorrelationExecutionId = null;
    notifyListeners();

    final definitionsResult = await _listDefinitions();
    if (definitionsResult.isError()) {
      _isLoading = false;
      _errorMessage = _messageFor(definitionsResult.exceptionOrNull()!);
      notifyListeners();
      return;
    }

    final executionsResult = await _listExecutions(
      requestedAfter: _now().subtract(const Duration(days: 3)),
      limit: 50,
    );
    if (executionsResult.isError()) {
      _isLoading = false;
      _errorMessage = _messageFor(executionsResult.exceptionOrNull()!);
      notifyListeners();
      return;
    }

    _definitions = definitionsResult.getOrThrow();
    _executions = executionsResult.getOrThrow();
    _selectedActionId = _resolveSelectedActionId();

    if (_featureFlags.enableAgentActionRemoteAudit) {
      final auditResult = await _listRecentRemoteAudit();
      auditResult.fold(
        (rows) {
          _remoteAuditEntries = rows;
          _remoteAuditLoadError = null;
        },
        (failure) {
          _remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
          _remoteAuditLoadError = _messageFor(failure);
        },
      );
    } else {
      _remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
      _remoteAuditLoadError = null;
    }

    _refreshElevatedRunnerReadiness();
    _isLoading = false;
    notifyListeners();
    unawaited(_syncTriggersForSelection());
    unawaited(_refreshSelectedSecretReport());
  }

  Future<void> prepareElevatedRunner() async {
    final prepare = _prepareElevatedActionRunner;
    if (prepare == null || !isElevatedAgentActionsEnabled) {
      return;
    }

    _isPreparingElevatedRunner = true;
    _errorMessage = null;
    notifyListeners();

    final result = await prepare();
    _isPreparingElevatedRunner = false;
    result.fold(
      (_) {
        _refreshElevatedRunnerReadiness();
        _errorMessage = null;
      },
      (failure) {
        _errorMessage = _messageFor(failure);
      },
    );
    notifyListeners();
  }

  void _refreshElevatedRunnerReadiness() {
    final readiness = _elevatedRunnerReadiness;
    final storage = _globalStorageContext;
    if (readiness == null || storage == null) {
      return;
    }
    readiness.refresh(storage);
  }

  Future<void> refreshRemoteAudit() async {
    if (!isRemoteAuditSectionVisible) {
      return;
    }

    _isLoadingRemoteAudit = true;
    notifyListeners();

    final auditResult = await _listRecentRemoteAudit();
    auditResult.fold(
      (rows) {
        _remoteAuditEntries = rows;
        _remoteAuditLoadError = null;
      },
      (failure) {
        _remoteAuditEntries = <AgentActionRemoteAuditRecord>[];
        _remoteAuditLoadError = _messageFor(failure);
      },
    );

    _isLoadingRemoteAudit = false;
    notifyListeners();
  }

  String buildRemoteAuditJsonExport() {
    return _remoteAuditExport.buildJson(_remoteAuditEntries);
  }

  /// Resets execution history filters, selects the audited action id, and highlights
  /// the audited execution id when that execution is visible after the in-memory
  /// list is updated. When the execution is missing from the list loaded by `load`,
  /// loads it once via `GetAgentActionExecution` and merges it into the cache when
  /// the stored `action_id` matches the audit row.
  ///
  /// Correlates a remote audit row with the local history panel (filters, selection,
  /// highlight). See [AgentActionRemoteAuditFocusResult] for failure reasons.
  Future<AgentActionRemoteAuditFocusResult> focusExecutionFromRemoteAudit(
    AgentActionRemoteAuditRecord record,
  ) async {
    if (!isFeatureEnabled) {
      return AgentActionRemoteAuditFocusResult.featureDisabled;
    }

    final actionId = record.actionId?.trim();
    if (actionId == null || actionId.isEmpty) {
      return AgentActionRemoteAuditFocusResult.missingActionId;
    }

    _historyStatusFilter = null;
    _historySourceFilter = null;
    _historyPeriodFilter = AgentActionHistoryPeriod.all;
    _historyFailurePhaseFilter = null;

    final executionId = record.executionId?.trim();
    _selectedActionId = actionId;
    _auditCorrelationExecutionId = executionId != null && executionId.isNotEmpty ? executionId : null;

    notifyListeners();
    unawaited(_syncTriggersForSelection());

    if (executionId == null || executionId.isEmpty) {
      return AgentActionRemoteAuditFocusResult.succeeded;
    }

    final visible = filteredSelectedExecutions
        .where((AgentActionExecution e) => e.id == executionId)
        .toList(growable: false);
    if (visible.isNotEmpty) {
      if (!_auditRuntimeMatchesExecution(record, visible.single)) {
        _auditCorrelationExecutionId = null;
        notifyListeners();
        return AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch;
      }
      return AgentActionRemoteAuditFocusResult.succeeded;
    }

    final fetched = await _getExecution(executionId, hydrateCapturedOutput: false);
    if (fetched.isError()) {
      _auditCorrelationExecutionId = null;
      notifyListeners();
      return AgentActionRemoteAuditFocusResult.executionNotResolvable;
    }

    final execution = fetched.getOrThrow();
    if (execution.actionId.trim() != actionId) {
      _auditCorrelationExecutionId = null;
      notifyListeners();
      return AgentActionRemoteAuditFocusResult.executionNotResolvable;
    }

    if (!_auditRuntimeMatchesExecution(record, execution)) {
      _auditCorrelationExecutionId = null;
      notifyListeners();
      return AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch;
    }

    _mergeExecutionIntoCache(execution);

    if (!filteredSelectedExecutions.any((AgentActionExecution e) => e.id == executionId)) {
      _auditCorrelationExecutionId = null;
      notifyListeners();
      return AgentActionRemoteAuditFocusResult.executionNotResolvable;
    }

    return AgentActionRemoteAuditFocusResult.succeeded;
  }

  bool _auditRuntimeMatchesExecution(
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

  void _mergeExecutionIntoCache(AgentActionExecution execution) {
    final merged = <AgentActionExecution>[
      ..._executions.where((AgentActionExecution e) => e.id != execution.id),
      execution,
    ]..sort((AgentActionExecution a, AgentActionExecution b) => b.requestedAt.compareTo(a.requestedAt));
    _executions = merged;
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

  Future<void> setMaintenanceMode({required bool enabled}) async {
    final coordinator = _subsystemCoordinator;
    if (coordinator != null) {
      if (enabled) {
        await coordinator.enterMaintenanceMode();
      } else {
        await coordinator.exitMaintenanceMode();
      }
    } else {
      await _featureFlags.setEnableAgentActionsMaintenanceMode(enabled);
      final guard = _runtimeStateGuard;
      if (guard != null) {
        if (enabled) {
          guard.markMaintenance();
        } else if (isFeatureEnabled) {
          guard.markReady();
        }
      }
    }
    notifyListeners();
  }

  bool _allowsLocalManualOperation(AgentActionType actionType) {
    final guard = _runtimeStateGuard;
    if (guard == null) {
      return true;
    }

    return guard
        .ensureCanAcceptExecution(
          request: const AgentActionExecutionRequest(
            actionId: 'manual-probe',
            source: AgentActionRequestSource.localUi,
          ),
          actionType: actionType,
        )
        .isSuccess();
  }

  void setHistoryStatusFilter(AgentActionExecutionStatus? status) {
    if (_historyStatusFilter == status) {
      return;
    }

    _auditCorrelationExecutionId = null;
    _historyStatusFilter = status;
    notifyListeners();
  }

  void setHistorySourceFilter(AgentActionRequestSource? source) {
    if (_historySourceFilter == source) {
      return;
    }

    _auditCorrelationExecutionId = null;
    _historySourceFilter = source;
    notifyListeners();
  }

  void setHistoryPeriodFilter(AgentActionHistoryPeriod period) {
    if (_historyPeriodFilter == period) {
      return;
    }

    _auditCorrelationExecutionId = null;
    _historyPeriodFilter = period;
    notifyListeners();
  }

  void setHistoryFailurePhaseFilter(String? phase) {
    final normalized = phase?.trim();
    final resolved = normalized == null || normalized.isEmpty ? null : normalized;
    if (_historyFailurePhaseFilter == resolved) {
      return;
    }

    _auditCorrelationExecutionId = null;
    _historyFailurePhaseFilter = resolved;
    notifyListeners();
  }

  void setHistorySearchQuery(String query) {
    final normalized = query.trim();
    if (_historySearchQuery == normalized) {
      return;
    }

    _auditCorrelationExecutionId = null;
    _historySearchQuery = normalized;
    notifyListeners();
  }

  void setDefinitionTypeFilter(AgentActionType? type) {
    if (_definitionTypeFilter == type) {
      return;
    }

    _definitionTypeFilter = type;
    notifyListeners();
  }

  void setDefinitionSearchQuery(String query) {
    final normalized = query.trim();
    if (_definitionSearchQuery == normalized) {
      return;
    }

    _definitionSearchQuery = normalized;
    notifyListeners();
  }

  bool _matchesDefinitionListFilter(AgentActionDefinition definition) {
    if (_definitionTypeFilter != null && definition.type != _definitionTypeFilter) {
      return false;
    }
    if (_definitionSearchQuery.isEmpty) {
      return true;
    }
    final needle = _definitionSearchQuery.toLowerCase();
    if (definition.name.toLowerCase().contains(needle)) {
      return true;
    }
    if (definition.id.toLowerCase().contains(needle)) {
      return true;
    }
    return definition.type.name.toLowerCase().contains(needle);
  }

  bool _matchesHistoryFailurePhase(AgentActionExecution execution) {
    final filter = _historyFailurePhaseFilter;
    if (filter == null) {
      return true;
    }
    final phase = execution.failurePhase?.trim().toLowerCase();
    return phase != null && phase == filter.toLowerCase();
  }

  bool _matchesHistorySearch(AgentActionExecution execution) {
    if (_historySearchQuery.isEmpty) {
      return true;
    }

    final needle = _historySearchQuery.toLowerCase();
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

  Future<void> _refreshSelectedSecretReport() async {
    final definition = selectedDefinition;
    if (definition == null) {
      _selectedSecretReport = null;
      notifyListeners();
      return;
    }

    _selectedSecretReport = await _secretAvailabilityChecker.check(definition);
    notifyListeners();
  }

  void clearSecretOperationError() {
    if (_secretOperationErrorMessage == null) {
      return;
    }
    _secretOperationErrorMessage = null;
    notifyListeners();
  }

  Future<Result<Unit>> saveActionSecret({
    required String secretName,
    required String secretValue,
  }) async {
    final saveSecret = _saveAgentActionSecret;
    if (saveSecret == null) {
      return Failure(
        domain_errors.ValidationFailure('Action secret store is not available.'),
      );
    }

    _savingActionSecretName = secretName.trim();
    _secretOperationErrorMessage = null;
    notifyListeners();

    final result = await saveSecret(
      secretName: secretName,
      secretValue: secretValue,
    );

    _savingActionSecretName = null;
    result.fold(
      (_) {
        _secretOperationErrorMessage = null;
      },
      (failure) {
        _secretOperationErrorMessage = _messageFor(failure);
      },
    );
    await _refreshSelectedSecretReport();
    return result;
  }

  Future<Result<Unit>> deleteActionSecret(String secretName) async {
    final deleteSecret = _deleteAgentActionSecret;
    if (deleteSecret == null) {
      return Failure(
        domain_errors.ValidationFailure('Action secret store is not available.'),
      );
    }

    _deletingActionSecretName = secretName.trim();
    _secretOperationErrorMessage = null;
    notifyListeners();

    final result = await deleteSecret(secretName);

    _deletingActionSecretName = null;
    result.fold(
      (_) {
        _secretOperationErrorMessage = null;
      },
      (failure) {
        _secretOperationErrorMessage = _messageFor(failure);
      },
    );
    await _refreshSelectedSecretReport();
    return result;
  }

  Future<void> loadDeveloperData7Connections({
    required String actionId,
    required String data7ConfigPath,
    String? selectedConnectionId,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
  }) async {
    _isLoadingDeveloperConnections = true;
    _developerConnectionLookupMessage = null;
    notifyListeners();

    final result = await _listDeveloperData7Connections(
      DeveloperData7ConnectionLookupRequest(
        actionId: actionId.trim(),
        data7ConfigPath: AgentActionPathReference(originalPath: data7ConfigPath.trim()),
        pathPolicy: pathPolicy,
        selectedConnectionId: selectedConnectionId,
      ),
    );

    result.fold(
      (lookup) {
        _developerConnections = lookup.connections;
        _resolvedDeveloperData7ConfigPath = lookup.resolvedConfigPath.displayPath;
        _usedDefaultDeveloperData7ConfigPath = lookup.usedDefaultLocation;
        _developerConnectionLookupMessage = null;
      },
      (failure) {
        _developerConnections = <DeveloperData7ConnectionOption>[];
        _resolvedDeveloperData7ConfigPath = null;
        _usedDefaultDeveloperData7ConfigPath = false;
        _developerConnectionLookupMessage = _messageFor(failure);
      },
    );

    _isLoadingDeveloperConnections = false;
    notifyListeners();
  }

  void clearDeveloperData7Connections({bool notify = true}) {
    _developerConnections = <DeveloperData7ConnectionOption>[];
    _developerConnectionLookupMessage = null;
    _resolvedDeveloperData7ConfigPath = null;
    _usedDefaultDeveloperData7ConfigPath = false;
    _isLoadingDeveloperConnections = false;
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> saveCommandLineAction({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final trimmedWorkingDirectory = workingDirectory?.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: CommandLineActionConfig(
        command: command.trim(),
        workingDirectory: _optionalPathReference(
          trimmedWorkingDirectory,
          pathChangePolicy: pathChangePolicy,
        ),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<void> saveExecutableAction({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final trimmedWorkingDirectory = workingDirectory?.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: ExecutableActionConfig(
        executablePath: _pathReference(
          executablePath.trim(),
          pathChangePolicy: pathChangePolicy,
        ),
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: _optionalPathReference(
          trimmedWorkingDirectory,
          pathChangePolicy: pathChangePolicy,
        ),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<void> saveScriptAction({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final trimmedInterpreterPath = interpreterPath?.trim();
    final trimmedWorkingDirectory = workingDirectory?.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: ScriptActionConfig(
        scriptPath: AgentActionPathReference(
          originalPath: scriptPath.trim(),
        ),
        interpreterPath: trimmedInterpreterPath == null || trimmedInterpreterPath.isEmpty
            ? null
            : AgentActionPathReference(
                originalPath: trimmedInterpreterPath,
              ),
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: trimmedWorkingDirectory == null || trimmedWorkingDirectory.isEmpty
            ? null
            : AgentActionPathReference(
                originalPath: trimmedWorkingDirectory,
              ),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<void> saveJarAction({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final trimmedJavaPath = javaExecutablePath?.trim();
    final trimmedWorkingDirectory = workingDirectory?.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: JarActionConfig(
        jarPath: AgentActionPathReference(
          originalPath: jarPath.trim(),
        ),
        javaExecutablePath: trimmedJavaPath == null || trimmedJavaPath.isEmpty
            ? null
            : AgentActionPathReference(
                originalPath: trimmedJavaPath,
              ),
        arguments: List<String>.unmodifiable(arguments),
        workingDirectory: trimmedWorkingDirectory == null || trimmedWorkingDirectory.isEmpty
            ? null
            : AgentActionPathReference(
                originalPath: trimmedWorkingDirectory,
              ),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<void> saveEmailAction({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: EmailActionConfig(
        smtpProfileId: smtpProfileId.trim(),
        from: from.trim(),
        to: List<String>.unmodifiable(to),
        cc: List<String>.unmodifiable(cc),
        bcc: List<String>.unmodifiable(bcc),
        subjectTemplate: subjectTemplate.trim(),
        bodyTemplate: bodyTemplate.trim(),
        attachmentPaths: List<AgentActionPathReference>.unmodifiable(attachmentPaths),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<void> saveComObjectAction({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: ComObjectActionConfig(
        progId: progId.trim(),
        memberName: memberName.trim(),
        arguments: Map<String, Object?>.unmodifiable(arguments),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<void> saveDeveloperData7Action({
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
  }) async {
    if (!canSaveAction) {
      return;
    }

    _isSaving = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final trimmedActionId = actionId?.trim();
    final trimmedDescription = description?.trim();
    final trimmedData7ConfigPath = data7ConfigPath?.trim() ?? '';
    final trimmedConnectionId = connectionId.trim();
    final existing = _existingDefinition(trimmedActionId);
    final definition = AgentActionDefinition(
      id: existing?.id ?? _uuid.v4(),
      name: name.trim(),
      description: trimmedDescription == null || trimmedDescription.isEmpty ? null : trimmedDescription,
      state: state,
      config: DeveloperActionConfig.data7Executor(
        executorPath: _pathReference(executorPath.trim()),
        projectPath: _pathReference(projectPath.trim()),
        data7ConfigPath: _pathReference(trimmedData7ConfigPath),
        connectionId: trimmedConnectionId,
        connectionLabel: connectionLabel.trim().isEmpty ? trimmedConnectionId : connectionLabel.trim(),
      ),
      policies: _policiesForSave(
        existing: existing,
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
        encodingPolicy: encodingPolicy,
        capturePolicy: capturePolicy,
        queuePolicy: queuePolicy,
        pathPolicy: pathPolicy,
      ),
      definitionVersion: existing?.definitionVersion ?? 1,
      createdAt: existing?.createdAt ?? _now(),
      updatedAt: _now(),
    );

    await _persistDefinition(definition);
  }

  Future<bool> exportBundleToFile(String filePath) async {
    if (!canTransferBundle) {
      return false;
    }

    final selectedId = _selectedActionId;
    final actionIds = selectedId == null ? null : <String>[selectedId];

    _isTransferringBundle = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _exportBundle(actionIds: actionIds);
    if (result.isError()) {
      _isTransferringBundle = false;
      _errorMessage = _messageFor(result.exceptionOrNull()!);
      notifyListeners();
      return false;
    }

    try {
      await File(filePath).writeAsString(result.getOrThrow());
    } on IOException {
      _isTransferringBundle = false;
      _errorMessage =
          'Nao foi possivel gravar o arquivo de exportacao. Verifique o caminho e as permissoes.';
      notifyListeners();
      return false;
    }

    _isTransferringBundle = false;
    notifyListeners();
    return true;
  }

  Future<ImportAgentActionsBundleSummary?> importBundleFromFile(String filePath) async {
    if (!canTransferBundle) {
      return null;
    }

    _isTransferringBundle = true;
    _errorMessage = null;
    notifyListeners();

    late final String payload;
    try {
      payload = await File(filePath).readAsString();
    } on IOException {
      _isTransferringBundle = false;
      _errorMessage =
          'Nao foi possivel ler o arquivo de importacao. Verifique o caminho e as permissoes.';
      notifyListeners();
      return null;
    }

    final result = await _importBundle(payload);
    if (result.isError()) {
      _isTransferringBundle = false;
      _errorMessage = _messageFor(result.exceptionOrNull()!);
      notifyListeners();
      return null;
    }

    final summary = result.getOrThrow();
    _isTransferringBundle = false;
    await load();
    return summary;
  }

  Future<void> deleteSelectedAction() async {
    final definition = selectedDefinition;
    if (definition == null || !canDeleteSelected) {
      return;
    }

    _isDeleting = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final result = await _deleteDefinition(definition.id);
    var shouldReload = false;
    result.fold(
      (_) {
        _selectedActionId = null;
        shouldReload = true;
      },
      (failure) {
        _errorMessage = _messageFor(failure);
      },
    );

    _isDeleting = false;
    if (shouldReload) {
      await load();
      return;
    }

    notifyListeners();
  }

  void selectAction(String actionId) {
    if (_selectedActionId == actionId) {
      return;
    }

    _auditCorrelationExecutionId = null;
    _selectedActionId = actionId;
    notifyListeners();
    unawaited(_syncTriggersForSelection());
    unawaited(_refreshSelectedSecretReport());
  }

  Future<void> refreshTriggersForSelection() => _syncTriggersForSelection();

  void clearTriggerOperationError() {
    if (_errorMessage == null) {
      return;
    }

    _errorMessage = null;
    notifyListeners();
  }

  Future<bool> saveTrigger(AgentActionTrigger trigger) async {
    if (!canManageTriggers || _isSavingTrigger) {
      return false;
    }

    _isSavingTrigger = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _saveTrigger(trigger);
    var ok = false;
    result.fold(
      (_) {
        ok = true;
      },
      (Exception failure) {
        _errorMessage = _messageFor(failure);
      },
    );

    _isSavingTrigger = false;
    if (ok) {
      await _syncTriggersForSelection();
    } else {
      notifyListeners();
    }

    return ok;
  }

  Future<void> deleteTrigger(String triggerId) async {
    final trimmedId = triggerId.trim();
    if (!isFeatureEnabled || trimmedId.isEmpty || _deletingTriggerIds.contains(trimmedId)) {
      return;
    }

    _deletingTriggerIds.add(trimmedId);
    _errorMessage = null;
    notifyListeners();

    final result = await _deleteTrigger(trimmedId);
    result.fold(
      (_) {},
      (failure) {
        _errorMessage = _messageFor(failure);
      },
    );

    _deletingTriggerIds.remove(trimmedId);
    await _syncTriggersForSelection();
  }

  Future<void> runSelectedAction() async {
    final definition = selectedDefinition;
    if (definition == null || !canRunSelected) {
      return;
    }

    _isRunning = true;
    _errorMessage = null;
    notifyListeners();

    final result = await _runAction(
      AgentActionExecutionRequest(
        actionId: definition.id,
        source: AgentActionRequestSource.localUi,
      ),
    );

    result.fold(
      (_) {},
      (failure) {
        _errorMessage = _messageFor(failure);
      },
    );

    _isRunning = false;
    await load();
  }

  Future<void> testSelectedAction() async {
    final definition = selectedDefinition;
    if (definition == null || !canTestSelected) {
      return;
    }

    _isTesting = true;
    _errorMessage = null;
    _lastTestedActionId = null;
    _lastTestCanRun = null;
    _clearLastTestPreviewState();
    notifyListeners();

    final result = await _testDefinition(definition.id);
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      _lastTestedActionId = definition.id;
      _lastTestCanRun = false;
      _errorMessage = _messageFor(failure);
      _applyTestFailurePreview(failure);
      _isTesting = false;
      notifyListeners();
      return;
    }

    final preflight = result.getOrThrow();
    _lastTestedActionId = definition.id;
    _lastTestCanRun = preflight.canRun;
    _lastTestDiagnostics = preflight.redactedDiagnostics;

    final previewResult = await _previewDefinition(definition.id);
    previewResult.fold(
      (preview) {
        _lastTestCommandPreview = preview.redactedCommandPreview;
        _lastTestDiagnostics = <String, Object?>{
          ..._lastTestDiagnostics,
          ...preview.redactedDiagnostics,
        };
        _lastTestPreviewErrorMessage = null;
      },
      (failure) {
        _lastTestCommandPreview = null;
        _lastTestPreviewErrorMessage = _messageFor(failure);
      },
    );

    _isTesting = false;
    notifyListeners();
  }

  Future<void> cancelExecution(AgentActionExecution execution) async {
    if (!canCancelExecution(execution)) {
      return;
    }

    _cancellingExecutionIds.add(execution.id);
    _errorMessage = null;
    notifyListeners();

    final result = await _cancelExecution(execution.id);
    result.fold(
      (_) {},
      (failure) {
        _errorMessage = _messageFor(failure);
      },
    );

    _cancellingExecutionIds.remove(execution.id);
    await load();
  }

  String? _resolveSelectedActionId() {
    final selectedId = _selectedActionId;
    if (selectedId != null && _definitions.any((definition) => definition.id == selectedId)) {
      return selectedId;
    }
    if (_definitions.isEmpty) {
      return null;
    }

    return _definitions.first.id;
  }

  DateTime? _historyPeriodStart() {
    return switch (_historyPeriodFilter) {
      AgentActionHistoryPeriod.all => null,
      AgentActionHistoryPeriod.last24Hours => _now().subtract(const Duration(hours: 24)),
      AgentActionHistoryPeriod.last3Days => _now().subtract(const Duration(days: 3)),
    };
  }

  String _messageFor(Exception failure) {
    return AgentActionFailureDiagnosticsResolver.userMessage(failure);
  }

  void _applyTestFailurePreview(Exception failure) {
    _lastTestCommandPreview = null;
    _lastTestPreviewErrorMessage = _messageFor(failure);
    if (failure is ActionFailure) {
      _lastTestDiagnostics = const AgentActionFailureDiagnosticsResolver()
          .redactedDiagnosticsForTestPreview(failure);
    } else {
      _lastTestDiagnostics = const <String, Object?>{};
    }
  }

  AgentActionDefinition? _existingDefinition(String? actionId) {
    if (actionId == null || actionId.isEmpty) {
      return null;
    }

    return _definitions.where((definition) => definition.id == actionId).firstOrNull;
  }

  AgentActionPathReference _pathReference(
    String originalPath, {
    AgentActionPathChangePolicy? pathChangePolicy,
  }) {
    return AgentActionPathReference(
      originalPath: originalPath,
      pathChangePolicy: pathChangePolicy,
    );
  }

  AgentActionPathReference? _optionalPathReference(
    String? originalPath, {
    AgentActionPathChangePolicy? pathChangePolicy,
  }) {
    final trimmed = originalPath?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return _pathReference(trimmed, pathChangePolicy: pathChangePolicy);
  }

  AgentActionDefinitionPolicies _policiesForSave({
    required AgentActionDefinition? existing,
    required AgentActionNotificationPolicy notificationPolicy,
    required AgentActionRetryPolicy retryPolicy,
    required AgentActionTimeoutPolicy timeoutPolicy,
    required AgentActionEnvironmentPolicy environmentPolicy,
    required AgentActionExitCodePolicy exitCodePolicy,
    required AgentActionProcessPolicy processPolicy,
    required AgentActionLifecyclePolicy lifecyclePolicy,
    required AgentActionRemotePolicy remotePolicy,
    required AgentActionElevatedPolicy elevatedPolicy,
    AgentActionContextPolicy? contextPolicy,
    AgentActionEncodingPolicy? encodingPolicy,
    AgentActionCapturePolicy? capturePolicy,
    AgentActionQueuePolicy? queuePolicy,
    AgentActionPathPolicy? pathPolicy,
  }) {
    return (existing?.policies ?? const AgentActionDefinitionPolicies()).copyWith(
      notification: notificationPolicy,
      retry: retryPolicy,
      timeout: timeoutPolicy,
      environment: environmentPolicy,
      exitCode: exitCodePolicy,
      process: processPolicy,
      lifecycle: lifecyclePolicy,
      remote: remotePolicy,
      elevated: elevatedPolicy,
      context: contextPolicy,
      encoding: encodingPolicy ?? existing?.policies.encoding,
      capture: capturePolicy ?? existing?.policies.capture,
      queue: queuePolicy ?? existing?.policies.queue,
      path: pathPolicy ?? existing?.policies.path,
    );
  }

  Future<void> _persistDefinition(AgentActionDefinition definition) async {
    final result = await _saveDefinition(definition);
    var shouldReload = false;
    result.fold(
      (savedDefinition) {
        _selectedActionId = savedDefinition.id;
        shouldReload = true;
      },
      (failure) {
        _errorMessage = _messageFor(failure);
      },
    );

    _isSaving = false;
    if (shouldReload) {
      await load();
      return;
    }

    notifyListeners();
  }

  void _clearLastTestPreviewState() {
    _lastTestCommandPreview = null;
    _lastTestPreviewErrorMessage = null;
    _lastTestDiagnostics = const <String, Object?>{};
  }

  Future<void> _syncTriggersForSelection() async {
    final definition = selectedDefinition;
    if (definition == null) {
      if (_triggers.isNotEmpty || _isLoadingTriggers) {
        _triggers = <AgentActionTrigger>[];
        _isLoadingTriggers = false;
        notifyListeners();
      }
      return;
    }

    _isLoadingTriggers = true;
    notifyListeners();

    final result = await _listTriggers(actionId: definition.id);
    if (result.isError()) {
      _isLoadingTriggers = false;
      _errorMessage = _messageFor(result.exceptionOrNull()!);
      _triggers = <AgentActionTrigger>[];
      notifyListeners();
      return;
    }

    final loaded = result.getOrThrow().toList(growable: false);
    loaded.sort((AgentActionTrigger left, AgentActionTrigger right) {
      final leftName = (left.name ?? '').trim();
      final rightName = (right.name ?? '').trim();
      final nameCompare = leftName.toLowerCase().compareTo(rightName.toLowerCase());
      if (nameCompare != 0) {
        return nameCompare;
      }

      return left.id.compareTo(right.id);
    });

    _triggers = loaded;
    _isLoadingTriggers = false;
    notifyListeners();
  }
}
