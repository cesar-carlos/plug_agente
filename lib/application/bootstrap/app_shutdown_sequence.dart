import 'dart:developer' as developer;

import 'package:get_it/get_it.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/services/agent_action_captured_output_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_execution_periodic_purge.dart';
import 'package:plug_agente/application/services/agent_action_remote_audit_periodic_purge.dart';
import 'package:plug_agente/application/services/elevated_bridge_artifacts_periodic_purge.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/core/services/i_app_infrastructure_shutdown_port.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';

/// Runs the post-hub teardown steps for application shutdown.
final class AppShutdownSequence {
  const AppShutdownSequence(this._getIt);

  final GetIt _getIt;

  Future<void> run({
    required Future<void> Function() runEarlyShutdownCoordinator,
    required Future<void> Function() dispatchAppCloseAgentActions,
    required Future<void> Function() applyOnAppExitPolicies,
    required void Function() shutdownOdbcWorker,
    required void Function() resetShutdownStateForTesting,
  }) async {
    _stopPeriodicPurges();
    _markAgentActionsDraining();
    await _cancelPendingElevatedExecutions();
    await dispatchAppCloseAgentActions();
    await applyOnAppExitPolicies();
    await runEarlyShutdownCoordinator();
    await _disposeSqlExecutionQueue();
    await _drainStreamingSessionCache();
    await _closeConnectionPool();
    await _disposeInfrastructureResources();
    await _disposeTrayService();
    shutdownOdbcWorker();
    resetShutdownStateForTesting();
  }

  void _stopPeriodicPurges() {
    if (_getIt.isRegistered<RpcIdempotencyCachePeriodicPurge>()) {
      _getIt<RpcIdempotencyCachePeriodicPurge>().stop();
    }

    if (_getIt.isRegistered<AgentActionRemoteAuditPeriodicPurge>()) {
      _getIt<AgentActionRemoteAuditPeriodicPurge>().stop();
    }

    if (_getIt.isRegistered<AgentActionCapturedOutputPeriodicPurge>()) {
      _getIt<AgentActionCapturedOutputPeriodicPurge>().stop();
    }

    if (_getIt.isRegistered<AgentActionExecutionPeriodicPurge>()) {
      _getIt<AgentActionExecutionPeriodicPurge>().stop();
    }

    if (_getIt.isRegistered<ElevatedBridgeArtifactsPeriodicPurge>()) {
      _getIt<ElevatedBridgeArtifactsPeriodicPurge>().stop();
    }
  }

  void _markAgentActionsDraining() {
    if (_getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      _getIt<AgentActionRuntimeStateGuard>().markDraining(
        reason: AgentActionRuntimeStateConstants.shutdownReason,
      );
    }
  }

  Future<void> _cancelPendingElevatedExecutions() async {
    if (!_getIt.isRegistered<IElevatedActionExecutionCanceller>()) {
      return;
    }
    try {
      await _getIt<IElevatedActionExecutionCanceller>().cancelAllPendingExecutions();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to cancel pending elevated executions during shutdown',
        name: 'app_shutdown_sequence',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _disposeSqlExecutionQueue() async {
    if (!_getIt.isRegistered<IDatabaseGateway>()) {
      return;
    }

    final gateway = _getIt<IDatabaseGateway>();
    if (gateway is! QueuedDatabaseGateway) {
      return;
    }

    final disposeResult = await gateway.disposeGracefully();
    disposeResult.fold(
      (_) => developer.log(
        'SQL execution queue disposed',
        name: 'app_shutdown_sequence',
        level: 800,
      ),
      (failure) => developer.log(
        'SQL execution queue dispose timed out; proceeding to pool close',
        name: 'app_shutdown_sequence',
        level: 900,
        error: failure,
      ),
    );
  }

  Future<void> _drainStreamingSessionCache() async {
    if (!_getIt.isRegistered<IOdbcStreamingSessionCache>()) {
      return;
    }

    final drainResult = await _getIt<IOdbcStreamingSessionCache>().drainCachedSessions();
    drainResult.fold(
      (_) => developer.log(
        'Streaming session cache drained',
        name: 'app_shutdown_sequence',
        level: 800,
      ),
      (failure) => developer.log(
        'Streaming session cache drain completed with errors; proceeding to pool close',
        name: 'app_shutdown_sequence',
        level: 900,
        error: failure,
      ),
    );
  }

  Future<void> _closeConnectionPool() async {
    if (!_getIt.isRegistered<IConnectionPool>()) {
      return;
    }
    await _getIt<IConnectionPool>().closeAll();
  }

  Future<void> _disposeInfrastructureResources() async {
    if (!_getIt.isRegistered<IAppInfrastructureShutdownPort>()) {
      return;
    }

    final port = _getIt<IAppInfrastructureShutdownPort>();
    await port.closeLocalDatabase();
    port.disposeMetricsCollectors();
    await port.disposeOdbcEventBridge();
  }

  Future<void> _disposeTrayService() async {
    if (!_getIt.isRegistered<ITrayService>()) {
      return;
    }
    try {
      _getIt<ITrayService>().dispose();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to dispose tray service during shutdown',
        name: 'app_shutdown_sequence',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
