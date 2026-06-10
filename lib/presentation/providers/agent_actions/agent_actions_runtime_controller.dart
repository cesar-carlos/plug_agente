import 'dart:async';

import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_subsystem_coordinator.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_definitions.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/prepare_elevated_action_runner.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/agent_action_preflight_settings.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';

typedef AgentActionsRuntimeStateChanged = void Function();

class AgentActionsLoadBootstrap {
  const AgentActionsLoadBootstrap({
    required this.historyController,
    required this.definitionsController,
    required this.executionsController,
    required this.remoteAuditController,
    required this.isPreflightValidForDefinition,
    required this.syncTriggersForSelection,
    required this.refreshSelectedSecretReport,
    required this.now,
  });

  final AgentActionsHistoryController historyController;
  final AgentActionsDefinitionsController definitionsController;
  final AgentActionsExecutionsController executionsController;
  final AgentActionsRemoteAuditController remoteAuditController;
  final bool Function(AgentActionDefinition definition) isPreflightValidForDefinition;
  final Future<void> Function() syncTriggersForSelection;
  final Future<void> Function() refreshSelectedSecretReport;
  final DateTime Function() now;
}

class AgentActionsRuntimeController {
  AgentActionsRuntimeController({
    required ListAgentActionDefinitions listDefinitions,
    required ListAgentActionExecutions listExecutions,
    required FeatureFlags featureFlags,
    required AgentActionRetentionSettings retentionSettings,
    required String Function(Exception failure) messageFor,
    required AgentActionsRuntimeStateChanged onStateChanged,
    AgentActionPreflightSettings? preflightSettings,
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    AgentActionSubsystemCoordinator? subsystemCoordinator,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    PrepareElevatedActionRunner? prepareElevatedActionRunner,
    GlobalStorageContext? globalStorageContext,
  }) : _listDefinitions = listDefinitions,
       _listExecutions = listExecutions,
       _featureFlags = featureFlags,
       _retentionSettings = retentionSettings,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged,
       _preflightSettings = preflightSettings,
       _runtimeStateGuard = runtimeStateGuard,
       _subsystemCoordinator = subsystemCoordinator,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _prepareElevatedActionRunner = prepareElevatedActionRunner,
       _globalStorageContext = globalStorageContext;

  final ListAgentActionDefinitions _listDefinitions;
  final ListAgentActionExecutions _listExecutions;
  final FeatureFlags _featureFlags;
  final AgentActionRetentionSettings _retentionSettings;
  final String Function(Exception failure) _messageFor;
  final AgentActionsRuntimeStateChanged _onStateChanged;
  final AgentActionPreflightSettings? _preflightSettings;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final AgentActionSubsystemCoordinator? _subsystemCoordinator;
  final ElevatedActionRunnerReadinessService? _elevatedRunnerReadiness;
  final PrepareElevatedActionRunner? _prepareElevatedActionRunner;
  final GlobalStorageContext? _globalStorageContext;

  bool isLoading = false;
  int loadGeneration = 0;
  String? errorMessage;
  bool isPreparingElevatedRunner = false;

  bool get isFeatureEnabled => _featureFlags.enableAgentActions;
  bool get isRemoteAgentActionsEnabled => _featureFlags.enableRemoteAgentActions;
  bool get isRemoteAdHocAgentActionsEnabled => _featureFlags.enableRemoteAdHocAgentActions;
  bool get isElevatedAgentActionsEnabled => _featureFlags.enableElevatedAgentActions;
  bool get isElevatedRunnerConfigured => _elevatedRunnerReadiness?.isConfigured ?? false;
  bool get isElevatedRunnerDegraded => _elevatedRunnerReadiness?.isDegraded ?? false;
  bool get isMaintenanceMode => _featureFlags.enableAgentActionsMaintenanceMode;
  bool get isMaintenanceStrictMode => _featureFlags.enableAgentActionsMaintenanceStrictMode;
  bool get isDangerousCommandWarnModeEnabled => _featureFlags.enableAgentActionDangerousCommandWarnMode;
  bool get isRemoteAuditSectionVisible => isFeatureEnabled && _featureFlags.enableAgentActionRemoteAudit;

  AgentActionRuntimeStateSnapshot get runtimeSubsystemSnapshot =>
      _runtimeStateGuard?.snapshot ?? const AgentActionRuntimeStateSnapshot(status: AgentActionSubsystemStatus.ready);

  int get executionRetentionDays => _retentionSettings.executionRetentionDays;
  int get remoteAuditRetentionDays => _retentionSettings.remoteAuditRetentionDays;
  int get capturedOutputRetentionHours => _retentionSettings.capturedOutputRetentionHours;
  bool get hasRetentionPersistedOverrides => _retentionSettings.hasPersistedOverrides;

  bool isActionTypeUnavailable(AgentActionType type) => runtimeSubsystemSnapshot.blocksType(type);

  bool allowsLocalManualOperation(AgentActionType actionType) {
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

  Future<void> load(AgentActionsLoadBootstrap bootstrap) async {
    final generation = ++loadGeneration;

    isLoading = true;
    errorMessage = null;
    bootstrap.definitionsController.lastOperationErrorMessage = null;
    bootstrap.remoteAuditController.clearCorrelation();
    _onStateChanged();

    final definitionsResult = await _listDefinitions();
    if (generation != loadGeneration) {
      return;
    }

    if (definitionsResult.isError()) {
      isLoading = false;
      errorMessage = _messageFor(definitionsResult.exceptionOrNull()!);
      bootstrap.executionsController.executions = <AgentActionExecution>[];
      bootstrap.executionsController.invalidateCaches();
      _onStateChanged();
      return;
    }

    final executionsResult = await _listExecutions(
      requestedAfter: bootstrap.historyController.periodStart(bootstrap.now),
      limit: bootstrap.historyController.executionFetchLimit(),
    );
    if (generation != loadGeneration) {
      return;
    }

    if (executionsResult.isError()) {
      isLoading = false;
      errorMessage = _messageFor(executionsResult.exceptionOrNull()!);
      _onStateChanged();
      return;
    }

    bootstrap.definitionsController.replaceDefinitions(definitionsResult.getOrThrow());
    bootstrap.executionsController.executions = executionsResult.getOrThrow();
    bootstrap.executionsController.invalidateCaches();
    bootstrap.definitionsController.syncSessionPreflightSnapshotHashes(
      isPreflightValid: bootstrap.isPreflightValidForDefinition,
    );
    bootstrap.definitionsController.selectedActionId = bootstrap.definitionsController.resolveSelectedActionId();

    await bootstrap.remoteAuditController.loadDuringBootstrap(
      remoteAuditEnabled: _featureFlags.enableAgentActionRemoteAudit,
    );
    if (generation != loadGeneration) {
      return;
    }

    refreshElevatedRunnerReadiness();
    isLoading = false;
    _onStateChanged();
    unawaited(bootstrap.syncTriggersForSelection());
    unawaited(bootstrap.refreshSelectedSecretReport());
  }

  Future<void> prepareElevatedRunner() async {
    final prepare = _prepareElevatedActionRunner;
    if (prepare == null || !isElevatedAgentActionsEnabled) {
      return;
    }

    isPreparingElevatedRunner = true;
    errorMessage = null;
    _onStateChanged();

    final result = await prepare();
    isPreparingElevatedRunner = false;
    result.fold(
      (_) {
        refreshElevatedRunnerReadiness();
        errorMessage = null;
      },
      (failure) {
        errorMessage = _messageFor(failure);
      },
    );
    _onStateChanged();
  }

  void refreshElevatedRunnerReadiness() {
    final readiness = _elevatedRunnerReadiness;
    final storage = _globalStorageContext;
    if (readiness == null || storage == null) {
      return;
    }
    readiness.refresh(storage);
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
    _onStateChanged();
  }

  Future<void> setMaintenanceStrictMode({required bool enabled}) async {
    await _featureFlags.setEnableAgentActionsMaintenanceStrictMode(enabled);
    _onStateChanged();
  }

  Future<void> savePreflightValidityDays(int days) async {
    final settings = _preflightSettings;
    if (settings == null) {
      return;
    }
    await settings.save(validityDays: days);
    _onStateChanged();
  }

  Future<void> clearPreflightPersistedOverride() async {
    final settings = _preflightSettings;
    if (settings == null) {
      return;
    }
    await settings.clearPersistedOverride();
    _onStateChanged();
  }

  Future<void> saveRetentionSettings({
    required int executionDays,
    required int remoteAuditDays,
    required int capturedOutputHours,
  }) async {
    await _retentionSettings.save(
      executionDays: executionDays,
      remoteAuditDays: remoteAuditDays,
      capturedOutputHours: capturedOutputHours,
    );
    _onStateChanged();
  }

  Future<void> clearRetentionPersistedOverrides() async {
    await _retentionSettings.clearPersistedOverrides();
    _onStateChanged();
  }
}
