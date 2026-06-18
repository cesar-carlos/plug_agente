import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_sequence.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/use_cases/apply_agent_action_on_app_exit_policies.dart';
import 'package:plug_agente/bootstrap/bootstrap_odbc_worker_locator.dart';
import 'package:plug_agente/core/di/get_it.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';

bool _appCloseActionsDispatched = false;

/// Resets module-level shutdown flags between tests.
///
/// Production shutdown does not call `GetIt.reset`; tests that exercise
/// [shutdownApp] should invoke this helper in tearDown when they need a
/// clean dispatch gate without tearing down the DI graph.
void resetShutdownStateForTesting() {
  _appCloseActionsDispatched = false;
}

/// Centralized shutdown of all application resources.
///
/// Shutdown order:
/// 0. Launch pending silent-update helper (before stopping the orchestrator)
/// 1. Stop periodic purges
/// 2. Mark agent-actions subsystem as draining
/// 3. Cancel pending elevated executions
/// 4. Dispatch app-close agent action triggers
/// 5. Apply onAppExit policies
/// 6. Hub disconnect and auto-update dispose via [AppShutdownCoordinator]
/// 7. Dispose SQL execution queue
/// 8. Drain ODBC streaming session cache
/// 9. Close ODBC connection pool
/// 10. Close local database (Drift), metrics, and ODBC event bridge
/// 11. Dispose tray service
/// 12. Shut down ODBC worker
Future<void> shutdownApp() async {
  await _launchPendingSilentUpdateHelperIfReady();

  await AppShutdownSequence(getIt).run(
    runEarlyShutdownCoordinator: _runEarlyShutdownCoordinator,
    dispatchAppCloseAgentActions: _dispatchAppCloseAgentActions,
    applyOnAppExitPolicies: _applyAgentActionOnAppExitPolicies,
    shutdownOdbcWorker: shutdownOdbcWorker,
    resetShutdownStateForTesting: resetShutdownStateForTesting,
  );
}

Future<void> _runEarlyShutdownCoordinator() async {
  if (getIt.isRegistered<AppShutdownCoordinator>()) {
    await getIt<AppShutdownCoordinator>().runEarlyShutdownPhase();
    return;
  }

  final shutdownCoordinator = AppShutdownCoordinator(
    hubConnectionShutdownRegistry: getIt.isRegistered<HubConnectionShutdownRegistry>()
        ? getIt<HubConnectionShutdownRegistry>()
        : HubConnectionShutdownRegistry(),
    transportClient: getIt.isRegistered<ITransportClient>() ? getIt<ITransportClient>() : null,
    autoUpdateOrchestrator: getIt.isRegistered<IAutoUpdateOrchestrator>() ? getIt<IAutoUpdateOrchestrator>() : null,
  );
  await shutdownCoordinator.runEarlyShutdownPhase();
}

Future<void> _launchPendingSilentUpdateHelperIfReady() async {
  if (!getIt.isRegistered<IAutoUpdateOrchestrator>()) {
    return;
  }
  final orchestrator = getIt<IAutoUpdateOrchestrator>();
  if (!await orchestrator.hasPendingDownloadedUpdate) {
    return;
  }
  try {
    final result = await orchestrator.applyPendingSilentUpdate(
      triggerAppClose: false,
    );
    result.fold(
      (_) => developer.log(
        'Pending silent update helper launched from shutdown path',
        name: 'bootstrap_app_shutdown',
        level: 800,
      ),
      (failure) => developer.log(
        'Failed to launch pending silent update helper during shutdown',
        name: 'bootstrap_app_shutdown',
        level: 900,
        error: failure,
      ),
    );
  } on Object catch (error, stackTrace) {
    developer.log(
      'Pending silent update helper launch threw during shutdown',
      name: 'bootstrap_app_shutdown',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _applyAgentActionOnAppExitPolicies() async {
  if (!getIt.isRegistered<ApplyAgentActionOnAppExitPolicies>()) {
    return;
  }

  try {
    final result = await getIt<ApplyAgentActionOnAppExitPolicies>()();
    result.fold(
      (counts) {
        if (counts.queuedCancelled > 0 || counts.runningHandled > 0) {
          developer.log(
            'Applied onAppExit policies '
            '(queued_cancelled=${counts.queuedCancelled}, running_handled=${counts.runningHandled})',
            name: 'bootstrap_app_shutdown',
            level: 800,
          );
        }
      },
      (failure) {
        developer.log(
          'Failed to apply agent action onAppExit policies',
          name: 'bootstrap_app_shutdown',
          level: 900,
          error: failure,
        );
      },
    );
  } on Object catch (error, stackTrace) {
    developer.log(
      'Failed to apply agent action onAppExit policies',
      name: 'bootstrap_app_shutdown',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _dispatchAppCloseAgentActions() async {
  if (_appCloseActionsDispatched) {
    return;
  }
  _appCloseActionsDispatched = true;

  if (!getIt.isRegistered<AgentActionTriggerScheduler>()) {
    return;
  }

  try {
    final scheduler = getIt<AgentActionTriggerScheduler>();
    final result = await scheduler.dispatchAppCloseTriggers();
    result.fold(
      (count) {
        if (count > 0) {
          developer.log(
            'Dispatched $count app-close agent action trigger(s)',
            name: 'bootstrap_app_shutdown',
            level: 800,
          );
        }
      },
      (failure) {
        developer.log(
          'Failed to dispatch app-close agent action triggers',
          name: 'bootstrap_app_shutdown',
          level: 900,
          error: failure,
        );
      },
    );
    scheduler.stop();
  } on Object catch (error, stackTrace) {
    developer.log(
      'Failed to dispatch app-close agent action triggers',
      name: 'bootstrap_app_shutdown',
      level: 900,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
