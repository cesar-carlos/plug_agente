import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_definition_save_options.dart';
import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_availability_checker.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/agent_actions_local_operation_policy.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_secret.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
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
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
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
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_preferences_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_provider_dependencies.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_runtime_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_save_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_secrets_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_secrets_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_selection_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_triggers_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_triggers_coordinator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

export 'agent_actions/agent_actions_history_controller.dart' show AgentActionHistoryPeriod;
export 'agent_actions/agent_actions_runtime_controller.dart' show AgentActionsLoadBootstrap;

part 'agent_actions/agent_actions_provider_capabilities.dart';
part 'agent_actions/agent_actions_provider_preferences_surface.dart';
part 'agent_actions/agent_actions_provider_read_model.dart';
part 'agent_actions/agent_actions_provider_runtime_surface.dart';
part 'agent_actions/agent_actions_provider_save_surface.dart';
part 'agent_actions/agent_actions_provider_secrets_surface.dart';

class AgentActionsProvider extends ChangeNotifier {
  AgentActionsProvider(
    AgentActionsProviderDependencies deps, {
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
  }) : _saveDefinition = deps.saveDefinition,
       _deleteDefinition = deps.deleteDefinition,
       _listTriggers = deps.listTriggers,
       _deleteTrigger = deps.deleteTrigger,
       _saveTrigger = deps.saveTrigger,
       _listDeveloperData7Connections = deps.listDeveloperData7Connections,
       _runAction = deps.runAction,
       _testDefinition = deps.testDefinition,
       _previewDefinition = deps.previewDefinition,
       _cancelExecution = deps.cancelExecution,
       _getExecution = deps.getExecution,
       _sliceCapturedOutput = deps.sliceCapturedOutput,
       _listRecentRemoteAudit = deps.listRecentRemoteAudit,
       _exportBundle = deps.exportBundle,
       _importBundle = deps.importBundle,
       _uuid = deps.uuid,
       _bundleFileGateway = deps.bundleFileGateway,
       _localOperationPolicy = AgentActionsLocalOperationPolicy(
         commandSafetyAssessor: deps.commandSafetyAssessor,
       ),
       _executionQueue = executionQueue,
       _triggerScheduler = triggerScheduler,
       _comObjectInvocationDiagnostics = comObjectInvocationDiagnostics,
       _now = now ?? DateTime.now,
       _historyController = historyController ?? AgentActionsHistoryController() {
    _runtimeController =
        runtimeController ??
        AgentActionsRuntimeController(
          listDefinitions: deps.listDefinitions,
          listExecutions: deps.listExecutions,
          featureFlags: deps.featureFlags,
          retentionSettings: deps.retentionSettings,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
          preflightSettings: preflightSettings,
          runtimeStateGuard: runtimeStateGuard,
          subsystemCoordinator: subsystemCoordinator,
          elevatedRunnerReadiness: elevatedRunnerReadiness,
          prepareElevatedActionRunner: prepareElevatedActionRunner,
          globalStorageContext: globalStorageContext,
        );
    _definitionsController =
        definitionsController ??
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
    _executionsController =
        executionsController ??
        AgentActionsExecutionsController(
          listExecutions: deps.listExecutions,
          runAction: _runAction,
          testDefinition: _testDefinition,
          previewDefinition: _previewDefinition,
          cancelExecution: _cancelExecution,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _triggersController =
        triggersController ??
        AgentActionsTriggersController(
          listTriggers: _listTriggers,
          saveTrigger: _saveTrigger,
          deleteTrigger: _deleteTrigger,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _secretsController =
        secretsController ??
        AgentActionsSecretsController(
          secretAvailabilityChecker: secretAvailabilityChecker ?? const AgentActionSecretAvailabilityChecker(),
          saveAgentActionSecret: saveAgentActionSecret ?? deps.saveAgentActionSecret,
          deleteAgentActionSecret: deleteAgentActionSecret ?? deps.deleteAgentActionSecret,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _remoteAuditController =
        remoteAuditController ??
        AgentActionsRemoteAuditController(
          listRecentRemoteAudit: _listRecentRemoteAudit,
          getExecution: _getExecution,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _bundleTransferController =
        bundleTransferController ??
        AgentActionsBundleTransferController(
          exportBundle: _exportBundle,
          importBundle: _importBundle,
          bundleFileGateway: _bundleFileGateway,
          messageFor: _messageFor,
          onStateChanged: notifyListeners,
        );
    _preferencesCoordinator = AgentActionsPreferencesCoordinator(
      historyController: _historyController,
      definitionsController: _definitionsController,
      executionsController: _executionsController,
      remoteAuditController: _remoteAuditController,
      onPreferencesChanged: notifyListeners,
      reloadExecutionsForPeriod: _reloadExecutionsForPeriod,
    );
    _secretsCoordinator = AgentActionsSecretsCoordinator(
      secretsController: _secretsController,
      selectedDefinition: () => selectedDefinition,
    );
    _remoteAuditController.bindFocusDependencies(
      definitionsController: _definitionsController,
      executionsController: _executionsController,
      historyController: _historyController,
      isFeatureEnabled: () => isFeatureEnabled,
      isRemoteAuditSectionVisible: () => isRemoteAuditSectionVisible,
      now: _now,
      syncTriggers: _syncTriggersForSelection,
      refreshSecrets: _secretsCoordinator.refreshForSelection,
    );
    _triggersCoordinator = AgentActionsTriggersCoordinator(
      triggersController: _triggersController,
      definitionsController: _definitionsController,
      canManageTriggers: () => canManageTriggers,
      isFeatureEnabled: () => isFeatureEnabled,
      selectedActionId: () => selectedDefinition?.id,
    );
    _saveCoordinator = AgentActionsSaveCoordinator(
      definitionsController: _definitionsController,
      executionsController: _executionsController,
      saveDefinition: _saveDefinition,
      uuid: _uuid,
      now: _now,
      messageFor: _messageFor,
      reload: load,
      setErrorMessage: (message) => _errorMessage = message,
    );
    _selectionCoordinator = AgentActionsSelectionCoordinator(
      definitionsController: _definitionsController,
      executionsController: _executionsController,
      remoteAuditController: _remoteAuditController,
      bundleTransferController: _bundleTransferController,
      notifyStateChanged: notifyListeners,
      setErrorMessage: (message) => _errorMessage = message,
      reload: load,
      syncTriggersForSelection: _syncTriggersForSelection,
      refreshSelectedSecretReport: _secretsCoordinator.refreshForSelection,
      selectedDefinition: () => selectedDefinition,
      canDeleteSelected: () => canDeleteSelected,
      canRunSelected: () => canRunSelected,
      canTestSelected: () => canTestSelected,
      canCancelExecution: canCancelExecution,
      canTransferBundle: () => canTransferBundle,
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
  final IAgentActionsBundleFileGateway _bundleFileGateway;
  final AgentActionsLocalOperationPolicy _localOperationPolicy;
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
  late final AgentActionsPreferencesCoordinator _preferencesCoordinator;
  late final AgentActionsSecretsCoordinator _secretsCoordinator;
  late final AgentActionsTriggersCoordinator _triggersCoordinator;
  late final AgentActionsSaveCoordinator _saveCoordinator;
  late final AgentActionsSelectionCoordinator _selectionCoordinator;

  int _periodReloadGeneration = 0;
  String? _errorMessage;

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

  bool canSetDefinitionActive(String? actionId, {required bool draftModified}) =>
      _definitionsController.canSetDefinitionActive(actionId, draftModified: draftModified);

  bool isPreflightValidForDefinition(AgentActionDefinition definition) =>
      _definitionsController.isPreflightValidForDefinition(definition);

  bool isPreflightExpiredForDefinition(AgentActionDefinition definition) =>
      _definitionsController.isPreflightExpiredForDefinition(definition);

  DateTime? preflightExpiresAtForDefinition(AgentActionDefinition definition) =>
      _definitionsController.preflightExpiresAtForDefinition(definition);

  bool hasCancellationInProgress(String executionId) => _executionsController.hasCancellationInProgress(executionId);

  bool isDeletingTrigger(String triggerId) => _triggersCoordinator.isDeletingTrigger(triggerId);

  bool canCancelExecution(AgentActionExecution execution) => _executionsController.canCancelExecution(
    execution: execution,
    isFeatureEnabled: isFeatureEnabled,
  );

  Future<void> load() => _runtimeController.load(
    AgentActionsLoadBootstrap(
      historyController: _historyController,
      definitionsController: _definitionsController,
      executionsController: _executionsController,
      remoteAuditController: _remoteAuditController,
      isPreflightValidForDefinition: isPreflightValidForDefinition,
      syncTriggersForSelection: _syncTriggersForSelection,
      refreshSelectedSecretReport: _secretsCoordinator.refreshForSelection,
      now: _now,
    ),
  );

  Future<void> refreshRemoteAudit() => _remoteAuditController.refreshWhenSectionVisible();

  String buildRemoteAuditJsonExport() => _remoteAuditController.buildJsonExport();

  Future<AgentActionRemoteAuditFocusResult> focusExecutionFromRemoteAudit(
    AgentActionRemoteAuditRecord record,
  ) => _remoteAuditController.focusExecutionFromRecord(record);

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

  Future<bool> exportBundleToFile(String filePath, {required AppLocalizations l10n}) =>
      _selectionCoordinator.exportBundleToFile(filePath, l10n: l10n);

  Future<ImportAgentActionsBundleSummary?> importBundleFromFile(
    String filePath, {
    required AppLocalizations l10n,
  }) => _selectionCoordinator.importBundleFromFile(filePath, l10n: l10n);

  Future<void> deleteSelectedAction() => _selectionCoordinator.deleteSelectedAction();

  void selectAction(String actionId) => _selectionCoordinator.selectAction(actionId);

  Future<void> refreshTriggersForSelection() => _triggersCoordinator.refreshTriggersForSelection();

  void clearTriggerOperationError() => _triggersCoordinator.clearTriggerOperationError();

  Future<bool> saveTrigger(AgentActionTrigger trigger) => _triggersCoordinator.saveTrigger(trigger);

  Future<void> deleteTrigger(String triggerId) => _triggersCoordinator.deleteTrigger(triggerId);

  Future<void> runSelectedAction({bool dangerousCommandConfirmed = false}) =>
      _selectionCoordinator.runSelectedAction(dangerousCommandConfirmed: dangerousCommandConfirmed);

  Future<void> testSelectedAction() => _selectionCoordinator.testSelectedAction();

  Future<void> cancelExecution(AgentActionExecution execution) => _selectionCoordinator.cancelExecution(execution);

  String _messageFor(Exception failure) => AgentActionFailureDiagnosticsResolver.userMessage(failure);

  Future<void> _syncTriggersForSelection() => _triggersCoordinator.refreshTriggersForSelection();
}
