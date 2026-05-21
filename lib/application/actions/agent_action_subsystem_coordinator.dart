import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';

/// Coordinates draining, scheduler stop and feature-flag transitions for agent actions.
class AgentActionSubsystemCoordinator {
  AgentActionSubsystemCoordinator(
    this._runtimeStateGuard,
    this._scheduler,
    this._featureFlags,
  );

  final AgentActionRuntimeStateGuard _runtimeStateGuard;
  final AgentActionTriggerScheduler _scheduler;
  final FeatureFlags _featureFlags;

  Future<void> enterMaintenanceMode() async {
    _runtimeStateGuard.markDraining(
      reason: AgentActionRuntimeStateConstants.enteringMaintenanceModeReason,
    );
    _scheduler.stop();
    await _featureFlags.setEnableAgentActionsMaintenanceMode(true);
    _runtimeStateGuard.markMaintenance();
  }

  Future<void> exitMaintenanceMode() async {
    await _featureFlags.setEnableAgentActionsMaintenanceMode(false);
    await _restoreOperationalState(resumeScheduler: true);
  }

  Future<void> disableRemoteAgentActions() async {
    _runtimeStateGuard.markDraining(
      reason: AgentActionRuntimeStateConstants.remoteProtocolRollbackReason,
    );
    _scheduler.stop();
    await _featureFlags.setEnableRemoteAgentActions(false);
    await _restoreOperationalState(resumeScheduler: true);
  }

  Future<void> _restoreOperationalState({required bool resumeScheduler}) async {
    if (!_featureFlags.enableAgentActions) {
      _runtimeStateGuard.markDisabled();
      return;
    }

    if (_featureFlags.enableAgentActionsMaintenanceMode) {
      _runtimeStateGuard.markMaintenance();
      return;
    }

    _runtimeStateGuard.markReady();

    if (!resumeScheduler || _scheduler.isBootstrapDisabled) {
      return;
    }

    final startResult = await _scheduler.start();
    startResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'Failed to restart agent action scheduler after operational transition',
          name: 'agent_action_subsystem_coordinator',
          level: 900,
          error: failure,
        );
      },
    );
  }
}
