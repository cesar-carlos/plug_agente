import 'dart:developer' as developer;

import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_outcome.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_runner_dependencies.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';

class DeferredBootPhaseRunner {
  DeferredBootPhaseRunner({
    required AgentActionsBootPhasesContract agentActionsBootPhases,
    DeferredBootPhaseRunnerDependencies? dependencies,
    RuntimeCapabilities? capabilities,
  }) : _agentActionsBootPhases = agentActionsBootPhases,
       _dependencies = dependencies ?? const DeferredBootPhaseRunnerDependencies(),
       _capabilities = capabilities;

  final AgentActionsBootPhasesContract _agentActionsBootPhases;
  final DeferredBootPhaseRunnerDependencies _dependencies;
  final RuntimeCapabilities? _capabilities;

  Future<DeferredBootPhaseOutcome> run() async {
    var schedulerStarted = false;
    var hadCriticalFailure = false;

    try {
      await _agentActionsBootPhases.runDeferredMaintenance();
      await _warmUpConnectionPool();
      schedulerStarted = await _agentActionsBootPhases.startSchedulerAndDispatchAppStart();
      await _startAutomaticUpdateChecks();
    } on Object catch (error, stackTrace) {
      hadCriticalFailure = true;
      developer.log(
        'Deferred bootstrap phases failed',
        name: 'deferred_boot_phase_runner',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }

    _applyRuntimeGuardOutcome(
      schedulerStarted: schedulerStarted,
      hadCriticalFailure: hadCriticalFailure,
    );

    return DeferredBootPhaseOutcome(
      schedulerStarted: schedulerStarted,
      hadCriticalFailure: hadCriticalFailure,
    );
  }

  void _applyRuntimeGuardOutcome({
    required bool schedulerStarted,
    required bool hadCriticalFailure,
  }) {
    final guard = _dependencies.runtimeStateGuard;
    if (guard == null) {
      return;
    }
    if (hadCriticalFailure) {
      guard.markDisabled(
        reason: AgentActionRuntimeStateConstants.deferredBootstrapCriticalFailureReason,
      );
      return;
    }
    if (!schedulerStarted) {
      guard.markDegraded(
        unavailableActionTypes: AgentActionType.values.toSet(),
        reason: AgentActionRuntimeStateConstants.deferredBootstrapSchedulerFailedReason,
      );
      return;
    }
    guard.markReady();
  }

  Future<void> _warmUpConnectionPool() async {
    final configResolver = _dependencies.activeConfigResolver;
    final pool = _dependencies.connectionPool;
    if (configResolver == null || pool == null) {
      return;
    }

    try {
      final configResult = await configResolver.resolveActiveOrFallback(
        metadataOnly: true,
      );

      await configResult.fold(
        (agentConfig) async {
          if (agentConfig.connectionString.isEmpty) {
            developer.log(
              'Skipping pool warm-up: no connection string configured',
              name: 'deferred_boot_phase_runner',
              level: 500,
            );
            return;
          }

          if (pool is IConnectionPoolWarmUp) {
            final warmUpPool = pool as IConnectionPoolWarmUp;
            final warmUpResult = await warmUpPool.warmUp(agentConfig.connectionString);
            warmUpResult.fold(
              (_) {},
              (Object failure) {
                developer.log(
                  'Pool warm-up cleanup failed (continuing without)',
                  name: 'deferred_boot_phase_runner',
                  level: 900,
                  error: failure,
                );
              },
            );
          }
        },
        (failure) {
          developer.log(
            'Skipping pool warm-up: config not available',
            name: 'deferred_boot_phase_runner',
            level: 500,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Pool warm-up failed (continuing without)',
        name: 'deferred_boot_phase_runner',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _startAutomaticUpdateChecks() async {
    try {
      final capabilities = _capabilities;
      if (capabilities != null && !capabilities.supportsAutoUpdate) {
        developer.log(
          'Auto-update skipped: not supported in current runtime mode',
          name: 'deferred_boot_phase_runner',
          level: 800,
        );
        return;
      }

      final orchestrator = _dependencies.autoUpdateOrchestrator;
      if (orchestrator == null) {
        return;
      }

      await orchestrator.startAutomaticChecks();
      if (orchestrator.isAvailable) {
        developer.log(
          'Auto-update automatic check scheduling started',
          name: 'deferred_boot_phase_runner',
          level: 800,
        );
      }
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start automatic update checks (continuing without)',
        name: 'deferred_boot_phase_runner',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
