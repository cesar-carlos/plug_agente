import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases_dependencies.dart';

abstract interface class AgentActionsBootPhasesContract {
  Future<void> runCritical();
  Future<void> runDeferredMaintenance();

  /// Returns `true` when the trigger scheduler started successfully.
  Future<bool> startSchedulerAndDispatchAppStart();
}

class AgentActionsBootPhases implements AgentActionsBootPhasesContract {
  const AgentActionsBootPhases({required AgentActionsBootPhasesDependencies dependencies})
    : _deps = dependencies;

  final AgentActionsBootPhasesDependencies _deps;

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
    final readiness = _deps.elevatedActionRunnerReadiness;
    final storageContext = _deps.globalStorageContext;
    if (readiness == null || storageContext == null) {
      return;
    }
    readiness.refresh(storageContext);
  }

  Future<void> _purgeStaleElevatedBridgeArtifacts() async {
    final cleanup = _deps.cleanupExpiredElevatedBridgeArtifacts;
    if (cleanup == null) {
      return;
    }

    try {
      final result = await cleanup();
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
    final purge = _deps.elevatedBridgeArtifactsPeriodicPurge;
    if (purge == null) {
      return;
    }

    try {
      purge.start();
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
      final result = await _deps.reconcileAgentActionExecutions();
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
      final result = await _deps.cleanupExpiredRpcIdempotencyCache();
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
      _deps.rpcIdempotencyCachePeriodicPurge.start();
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
      final result = await _deps.cleanupExpiredAgentActionRemoteAudit();
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
      _deps.agentActionRemoteAuditPeriodicPurge.start();
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
    final cleanup = _deps.cleanupAgentActionCapturedOutput;
    if (cleanup == null) {
      return;
    }

    try {
      final result = await cleanup();
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
    final purge = _deps.agentActionCapturedOutputPeriodicPurge;
    if (purge == null) {
      return;
    }

    try {
      purge.start();
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
      final result = await _deps.cleanupAgentActionExecutions();
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
      _deps.agentActionExecutionPeriodicPurge.start();
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
    final scheduler = _deps.agentActionTriggerScheduler;
    try {
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
        scheduler.stop();
      } on Object {
        // Bootstrap continues without agent actions when scheduler teardown fails.
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
    final scheduler = _deps.agentActionTriggerScheduler;
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
