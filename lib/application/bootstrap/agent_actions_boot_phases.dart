import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/services/agent_action_captured_output_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_execution_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_remote_audit_periodic_purge.dart';
import 'package:plug_agente/application/services/elevated_bridge_artifacts_periodic_purge.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_captured_output.dart';
import 'package:plug_agente/application/use_cases/cleanup_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_elevated_bridge_artifacts.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_rpc_idempotency_cache.dart';
import 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';

abstract interface class AgentActionsBootPhasesContract {
  Future<void> runCritical();
  Future<void> runDeferredMaintenance();

  /// Returns `true` when the trigger scheduler started successfully.
  Future<bool> startSchedulerAndDispatchAppStart();
}

class AgentActionsBootPhases implements AgentActionsBootPhasesContract {
  const AgentActionsBootPhases();

  @override
  Future<void> runCritical() async {
    _refreshElevatedActionRunnerReadiness();
    await _reconcileAgentActionExecutions();
  }

  @override
  Future<void> runDeferredMaintenance() async {
    await _purgeStaleElevatedBridgeArtifacts();
    await _clearOldAgentActionCapturedOutput();
    await _purgeOldAgentActionExecutions();
    await _purgeExpiredRpcIdempotencyCache();
    _startRpcIdempotencyPeriodicPurge();
    await _purgeExpiredAgentActionRemoteAudit();
    _startAgentActionCapturedOutputPeriodicPurge();
    _startAgentActionExecutionPeriodicPurge();
    _startAgentActionRemoteAuditPeriodicPurge();
    _startElevatedBridgeArtifactsPeriodicPurge();
  }

  @override
  Future<bool> startSchedulerAndDispatchAppStart() async {
    final schedulerStarted = await _startAgentActionScheduler();
    if (!schedulerStarted) {
      return false;
    }
    await _dispatchAppStartAgentActions();
    return true;
  }

  void _refreshElevatedActionRunnerReadiness() {
    if (!getIt.isRegistered<ElevatedActionRunnerReadinessService>()) {
      return;
    }
    getIt<ElevatedActionRunnerReadinessService>().refresh(getIt<GlobalStorageContext>());
  }

  Future<void> _purgeStaleElevatedBridgeArtifacts() async {
    if (!getIt.isRegistered<CleanupExpiredElevatedBridgeArtifacts>()) {
      return;
    }

    try {
      final result = await getIt<CleanupExpiredElevatedBridgeArtifacts>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count stale elevated bridge artifact file(s) during bootstrap',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge stale elevated bridge artifacts during bootstrap (continuing without)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge stale elevated bridge artifacts during bootstrap (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startElevatedBridgeArtifactsPeriodicPurge() {
    if (!getIt.isRegistered<ElevatedBridgeArtifactsPeriodicPurge>()) {
      return;
    }

    try {
      getIt<ElevatedBridgeArtifactsPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic elevated bridge artifact purge (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _reconcileAgentActionExecutions() async {
    try {
      final result = await getIt<ReconcileAgentActionExecutions>()();
      result.fold(
        (count) {
          if (count > 0) {
            developer.log(
              'Reconciled $count interrupted agent action execution(s) during bootstrap',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (failure) {
          developer.log(
            'Failed to reconcile agent action executions during bootstrap (continuing without)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to reconcile agent action executions during bootstrap (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _purgeExpiredRpcIdempotencyCache() async {
    try {
      final result = await getIt<CleanupExpiredRpcIdempotencyCache>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count expired RPC idempotency cache row(s) during bootstrap',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge expired RPC idempotency cache during bootstrap (continuing without)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge expired RPC idempotency cache during bootstrap (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startRpcIdempotencyPeriodicPurge() {
    try {
      getIt<RpcIdempotencyCachePeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic RPC idempotency cache purge (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _purgeExpiredAgentActionRemoteAudit() async {
    try {
      final result = await getIt<CleanupExpiredAgentActionRemoteAudit>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count old agent action remote audit row(s) during bootstrap',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge old agent action remote audit rows during bootstrap (continuing without)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge old agent action remote audit rows during bootstrap (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startAgentActionRemoteAuditPeriodicPurge() {
    try {
      getIt<AgentActionRemoteAuditPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic agent action remote audit purge (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _clearOldAgentActionCapturedOutput() async {
    if (!getIt.isRegistered<CleanupAgentActionCapturedOutput>()) {
      return;
    }

    try {
      final result = await getIt<CleanupAgentActionCapturedOutput>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Cleared captured output on $count agent action execution row(s) during bootstrap',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to clear old agent action captured output during bootstrap (continuing without)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to clear old agent action captured output during bootstrap (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startAgentActionCapturedOutputPeriodicPurge() {
    if (!getIt.isRegistered<AgentActionCapturedOutputPeriodicPurge>()) {
      return;
    }

    try {
      getIt<AgentActionCapturedOutputPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic agent action captured output purge (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _purgeOldAgentActionExecutions() async {
    try {
      final result = await getIt<CleanupAgentActionExecutions>()();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count old terminal agent action execution row(s) during bootstrap',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Failed to purge old agent action executions during bootstrap (continuing without)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to purge old agent action executions during bootstrap (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startAgentActionExecutionPeriodicPurge() {
    try {
      getIt<AgentActionExecutionPeriodicPurge>().start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to start periodic agent action execution history purge (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<bool> _startAgentActionScheduler() async {
    try {
      final scheduler = getIt<AgentActionTriggerScheduler>();
      final startResult = await scheduler.start();
      return startResult.fold(
        (snapshot) {
          developer.log(
            'Agent action scheduler started '
            '(scheduled: ${snapshot.scheduledCount}, skipped: ${snapshot.skippedCount}, '
            'issues: ${snapshot.issues.length})',
            name: 'agent_actions_boot_phases',
            level: snapshot.hasIssues ? 900 : 800,
          );
          return true;
        },
        (failure) {
          scheduler.stop();
          developer.log(
            'Failed to start agent action scheduler (continuing without temporal actions)',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
          return false;
        },
      );
    } on Exception catch (e, stackTrace) {
      try {
        getIt<AgentActionTriggerScheduler>().stop();
      } on Object {
        // Scheduler may not be registered; bootstrap continues without agent actions.
      }
      developer.log(
        'Failed to initialize agent action scheduler (continuing without)',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> _dispatchAppStartAgentActions() async {
    final scheduler = getIt<AgentActionTriggerScheduler>();
    try {
      final result = await scheduler.dispatchAppStartTriggers();
      result.fold(
        (count) {
          if (count > 0) {
            developer.log(
              'Dispatched $count app-start agent action trigger(s)',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (failure) {
          developer.log(
            'Failed to dispatch app-start agent action triggers',
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to dispatch app-start agent action triggers',
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
