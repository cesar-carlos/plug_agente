import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases_dependencies.dart';
import 'package:result_dart/result_dart.dart';

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

  Future<void> _runInitialPurge({
    required Future<Result<int>> Function()? purge,
    required String successLogSuffix,
    required String failureLogMessage,
    String Function(int count)? successLogBuilder,
  }) async {
    if (purge == null) {
      return;
    }

    try {
      final result = await purge();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              successLogBuilder?.call(count) ?? 'Purged $count $successLogSuffix',
              name: 'agent_actions_boot_phases',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            failureLogMessage,
            name: 'agent_actions_boot_phases',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        failureLogMessage,
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startPeriodicPurge({
    required void Function()? start,
    required String failureLogMessage,
  }) {
    if (start == null) {
      return;
    }

    try {
      start();
    } on Exception catch (e, stackTrace) {
      developer.log(
        failureLogMessage,
        name: 'agent_actions_boot_phases',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
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
    await _runInitialPurge(
      purge: _deps.cleanupExpiredElevatedBridgeArtifacts?.call,
      successLogSuffix: 'stale elevated bridge artifact file(s) during bootstrap',
      failureLogMessage:
          'Failed to purge stale elevated bridge artifacts during bootstrap (continuing without)',
    );
  }

  void _startElevatedBridgeArtifactsPeriodicPurge() {
    _startPeriodicPurge(
      start: _deps.elevatedBridgeArtifactsPeriodicPurge?.start,
      failureLogMessage:
          'Failed to start periodic elevated bridge artifact purge (continuing without)',
    );
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
    await _runInitialPurge(
      purge: _deps.cleanupExpiredRpcIdempotencyCache.call,
      successLogSuffix: 'expired RPC idempotency cache row(s) during bootstrap',
      failureLogMessage:
          'Failed to purge expired RPC idempotency cache during bootstrap (continuing without)',
    );
  }

  void _startRpcIdempotencyPeriodicPurge() {
    _startPeriodicPurge(
      start: _deps.rpcIdempotencyCachePeriodicPurge.start,
      failureLogMessage:
          'Failed to start periodic RPC idempotency cache purge (continuing without)',
    );
  }

  Future<void> _purgeExpiredAgentActionRemoteAudit() async {
    await _runInitialPurge(
      purge: _deps.cleanupExpiredAgentActionRemoteAudit.call,
      successLogSuffix: 'old agent action remote audit row(s) during bootstrap',
      failureLogMessage:
          'Failed to purge old agent action remote audit rows during bootstrap (continuing without)',
    );
  }

  void _startAgentActionRemoteAuditPeriodicPurge() {
    _startPeriodicPurge(
      start: _deps.agentActionRemoteAuditPeriodicPurge.start,
      failureLogMessage:
          'Failed to start periodic agent action remote audit purge (continuing without)',
    );
  }

  Future<void> _clearOldAgentActionCapturedOutput() async {
    await _runInitialPurge(
      purge: _deps.cleanupAgentActionCapturedOutput?.call,
      successLogSuffix: 'agent action execution row(s) during bootstrap',
      failureLogMessage:
          'Failed to clear old agent action captured output during bootstrap (continuing without)',
      successLogBuilder: (count) =>
          'Cleared captured output on $count agent action execution row(s) during bootstrap',
    );
  }

  void _startAgentActionCapturedOutputPeriodicPurge() {
    _startPeriodicPurge(
      start: _deps.agentActionCapturedOutputPeriodicPurge?.start,
      failureLogMessage:
          'Failed to start periodic agent action captured output purge (continuing without)',
    );
  }

  Future<void> _purgeOldAgentActionExecutions() async {
    await _runInitialPurge(
      purge: _deps.cleanupAgentActionExecutions.call,
      successLogSuffix: 'old terminal agent action execution row(s) during bootstrap',
      failureLogMessage:
          'Failed to purge old agent action executions during bootstrap (continuing without)',
    );
  }

  void _startAgentActionExecutionPeriodicPurge() {
    _startPeriodicPurge(
      start: _deps.agentActionExecutionPeriodicPurge.start,
      failureLogMessage:
          'Failed to start periodic agent action execution history purge (continuing without)',
    );
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
