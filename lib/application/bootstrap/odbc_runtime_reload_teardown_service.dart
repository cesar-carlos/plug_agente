import 'dart:developer' as developer;

import 'package:get_it/get_it.dart';
import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/core/constants/agent_action_runtime_state_constants.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_runtime_reload_teardown_port.dart';
import 'package:plug_agente/domain/repositories/i_odbc_streaming_session_cache.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';

class OdbcRuntimeReloadTeardownService implements IOdbcRuntimeReloadTeardownPort {
  OdbcRuntimeReloadTeardownService({required GetIt getIt}) : _getIt = getIt;

  final GetIt _getIt;

  @override
  bool markAgentActionsDraining() {
    if (!_getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      return false;
    }
    _getIt<AgentActionRuntimeStateGuard>().markDraining(
      reason: AgentActionRuntimeStateConstants.odbcRuntimeReloadReason,
    );
    return true;
  }

  @override
  void markAgentActionsReady() {
    if (!_getIt.isRegistered<AgentActionRuntimeStateGuard>()) {
      return;
    }
    _getIt<AgentActionRuntimeStateGuard>().markReady();
  }

  @override
  Future<void> disposeActionExecutionQueue() async {
    if (!_getIt.isRegistered<ActionExecutionQueue>()) {
      return;
    }

    final disposeResult = await _getIt<ActionExecutionQueue>().disposeGracefully();
    disposeResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'Action execution queue dispose timed out before ODBC reload; proceeding',
          name: 'odbc_runtime_reload_teardown',
          level: 900,
          error: failure,
        );
      },
    );
  }

  @override
  Future<void> disposeSqlExecutionQueue() async {
    if (!_getIt.isRegistered<IDatabaseGateway>()) {
      return;
    }

    final gateway = _getIt<IDatabaseGateway>();
    if (gateway is! QueuedDatabaseGateway) {
      return;
    }

    final disposeResult = await gateway.disposeGracefully();
    disposeResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'SQL execution queue dispose timed out before ODBC reload; proceeding',
          name: 'odbc_runtime_reload_teardown',
          level: 900,
          error: failure,
        );
      },
    );
  }

  @override
  Future<void> drainStreamingSessionCache() async {
    if (!_getIt.isRegistered<IOdbcStreamingSessionCache>()) {
      return;
    }

    final drainResult = await _getIt<IOdbcStreamingSessionCache>().drainCachedSessions();
    drainResult.fold(
      (_) {},
      (failure) {
        developer.log(
          'Streaming session cache drain completed with errors before ODBC reload',
          name: 'odbc_runtime_reload_teardown',
          level: 900,
          error: failure,
        );
      },
    );
  }

  @override
  Future<void> disconnectHubTransport() async {
    if (_getIt.isRegistered<AppShutdownCoordinator>()) {
      await _getIt<AppShutdownCoordinator>().disconnectHubTransport();
      return;
    }

    final shutdownCoordinator = AppShutdownCoordinator(
      hubConnectionShutdownRegistry: _getIt.isRegistered<HubConnectionShutdownRegistry>()
          ? _getIt<HubConnectionShutdownRegistry>()
          : HubConnectionShutdownRegistry(),
      transportClient: _getIt.isRegistered<ITransportClient>() ? _getIt<ITransportClient>() : null,
    );
    await shutdownCoordinator.disconnectHubTransport();
  }
}
