import 'dart:async';
import 'dart:developer' as developer;

import 'package:get_it/get_it.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_execution_abort_registry.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_sequence.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/update_maintenance_admission.dart';
import 'package:plug_agente/application/services/update_maintenance_coordinator.dart';
import 'package:plug_agente/bootstrap/bootstrap_app_shutdown.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_in_flight_execution_registry.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:result_dart/result_dart.dart';

class BootstrapUpdateMaintenance {
  BootstrapUpdateMaintenance(this._services);
  final GetIt _services;
  UpdateMaintenanceCoordinator? _coordinator;
  String? _operation;
  Future<Result<void>> Function()? _beforeClose;
  bool prepared = false;
  bool _resourcesClosureStarted = false;
  UpdateMaintenanceAdmission get admission => _services<UpdateMaintenanceAdmission>();

  void markRecoveryRequired(bool unknown) {
    if (_operation != null) {
      admission.transition(
        _operation!,
        unknown ? UpdateMaintenancePhase.dispatchUnknown : UpdateMaintenancePhase.recoveryRequired,
      );
    }
  }

  Future<Result<void>> prepare(String operation, {Future<Result<void>> Function()? beforeClose}) async {
    if (_operation != null && _operation != operation) {
      return Failure(domain.ConfigurationFailure('Outra atualização já está em preparação.'));
    }
    _operation = operation;
    _beforeClose = beforeClose;
    final sql = _services<SqlExecutionQueue>();
    final actions = _services<ActionExecutionQueue>();
    _coordinator ??= UpdateMaintenanceCoordinator(
      freezeAdmission: () {
        admission.transition(_operation!, UpdateMaintenancePhase.draining);
        AppShutdownSequence(_services).stopPeriodicPurgesForMaintenance();
        if (_services.isRegistered<HubConnectionShutdownRegistry>()) {
          _services<HubConnectionShutdownRegistry>().pauseWritersForMaintenance();
        }
        if (_services.isRegistered<AgentActionTriggerScheduler>()) _services<AgentActionTriggerScheduler>().stop();
        sql.pauseAdmissionForMaintenance(_operation!);
        actions.pauseAdmissionForMaintenance(_operation!);
      },
      restoreAdmission: () {
        if (_services.isRegistered<AgentActionTriggerScheduler>()) {
          _services<AgentActionTriggerScheduler>().resetAppCloseAfterMaintenance();
        }
        restoreShutdownAfterMaintenance();
        sql.resumeAdmissionAfterMaintenance(_operation!);
        actions.resumeAdmissionAfterMaintenance(_operation!);
        admission.transition(_operation!, UpdateMaintenancePhase.operational);
        AppShutdownSequence(_services).resumePeriodicPurgesAfterMaintenance();
        if (_services.isRegistered<HubConnectionShutdownRegistry>()) {
          _services<HubConnectionShutdownRegistry>().resumeWritersAfterMaintenance();
        }
        if (_services.isRegistered<AgentActionTriggerScheduler>()) {
          unawaited(
            restartSchedulerAfterMaintenance(_services<AgentActionTriggerScheduler>()).catchError((
              Object error,
              StackTrace stack,
            ) {
              developer.log('Scheduler restart after maintenance failed', error: error, stackTrace: stack);
            }),
          );
        }
      },
      isSafelyIdle: () =>
          sql.activeWorkers == 0 &&
          sql.queueSize == 0 &&
          actions.runningCount == 0 &&
          actions.queuedCount == 0 &&
          _nativeIdle() &&
          admission.idle &&
          (!_services.isRegistered<HubConnectionShutdownRegistry>() ||
              _services<HubConnectionShutdownRegistry>().maintenanceWritersIdle) &&
          AppShutdownSequence(_services).periodicPurgesIdle,
      applyExitPolicies: (_) async {
        try {
          await admission.internal(_operation!, applyUpdateExitPoliciesOnce);
          return const Success(unit);
        } on Object catch (error) {
          return Failure(
            domain.ConfigurationFailure.withContext(
              message: 'O encerramento das ações não foi confirmado.',
              cause: error,
            ),
          );
        }
      },
      beforeClose: () async => _beforeClose == null ? const Success(unit) : await _beforeClose!(),
      flushAndCloseLocalData: () async {
        confirmUpdateExitPoliciesForShutdown();
        _resourcesClosureStarted = true;
        admission.transition(_operation!, UpdateMaintenancePhase.resourcesClosed);
        final drained = await _services<IOdbcStreamingSessionCache>().drainCachedSessions();
        if (drained.isError()) return Failure(drained.exceptionOrNull()!);
        final closed = await _services<IConnectionPool>().closeAll();
        if (closed.isError()) return Failure(closed.exceptionOrNull()!);
        if (!_nativeIdle()) return Failure(domain.ConfigurationFailure('Existem recursos nativos pendentes.'));
        final settings = _services<IAppSettingsStore>();
        await settings.flushPendingPersistence();
        if (settings.lastPersistError != null) {
          return Failure(domain.ConfigurationFailure('As configurações não foram salvas.'));
        }
        await _services<AppDatabase>().checkpointAndCloseForUpdate();
        return const Success(unit);
      },
    );
    final result = await _coordinator!.prepare(operation);
    if (result.isError()) {
      final error = result.exceptionOrNull()!;
      if (_resourcesClosureStarted) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Os recursos foram fechados. O agente precisa ser reiniciado pelo serviço.',
            cause: error,
            context: const {'reason': 'maintenance_resources_closed', 'resources_closed': true},
          ),
        );
      }
      if (admission.blocked) {
        markRecoveryRequired(false);
      } else {
        _operation = null;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: error is domain.Failure ? error.message : 'A manutenção não foi concluída.',
          cause: error,
          context: {
            if (error is domain.Failure) ...error.context,
            'resources_closed': false,
            if (admission.blocked) 'outcome_unknown': true,
          },
        ),
      );
    }
    if (result.getOrThrow() != MaintenanceDecision.ready) {
      _operation = null;
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'A atualização foi adiada para aguardar o encerramento das operações.',
          context: const {'reason': 'maintenance_deferred', 'retryable': true},
        ),
      );
    }
    prepared = true;
    return const Success(unit);
  }

  bool _nativeIdle() {
    if (_services<OdbcInFlightExecutionRegistry>().hasUnconfirmedWork ||
        _services<ElevatedActionExecutionAbortRegistry>().hasPendingExecutions) {
      return false;
    }
    final pool = _services<IConnectionPool>();
    if (pool is! IConnectionPoolDiagnostics) return false;
    final diagnostics = (pool as IConnectionPoolDiagnostics).getHealthDiagnostics();
    for (final key in const [
      'lease_active_count',
      'native_active_count',
      'native_backend_active_count',
      'native_owned_connection_count',
      'native_pending_return_count',
      'native_unconfirmed_connection_count',
      'native_quarantined_pool_count',
      'tracked_owner_count',
    ]) {
      if ((diagnostics[key] as int? ?? 0) != 0) return false;
    }
    return diagnostics['config_drain_pending'] != true;
  }
}

Future<void> restartSchedulerAfterMaintenance(AgentActionTriggerScheduler scheduler) async {
  final result = await scheduler.start();
  if (result.isError()) throw result.exceptionOrNull()!;
}
