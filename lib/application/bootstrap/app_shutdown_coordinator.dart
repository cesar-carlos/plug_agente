import 'dart:developer' as developer;

import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';

/// Coordinates hub teardown so recovery timers are cancelled before transport
/// disconnect. Falls back to direct transport disconnect when no UI port is bound.
class AppShutdownCoordinator {
  AppShutdownCoordinator({
    required HubConnectionShutdownRegistry hubConnectionShutdownRegistry,
    ITransportClient? transportClient,
    IAutoUpdateOrchestrator? autoUpdateOrchestrator,
  }) : _hubConnectionShutdownRegistry = hubConnectionShutdownRegistry,
       _transportClient = transportClient,
       _autoUpdateOrchestrator = autoUpdateOrchestrator;

  final HubConnectionShutdownRegistry _hubConnectionShutdownRegistry;
  final ITransportClient? _transportClient;
  final IAutoUpdateOrchestrator? _autoUpdateOrchestrator;

  /// Stops auto-update scheduling and tears down the hub connection layer before
  /// the global shutdown sequence continues with agent actions and ODBC.
  Future<void> runEarlyShutdownPhase() async {
    await stopAutoUpdateOrchestrator();
    await disconnectHubTransport();
  }

  Future<void> stopAutoUpdateOrchestrator() async {
    final orchestrator = _autoUpdateOrchestrator;
    if (orchestrator == null) {
      return;
    }
    try {
      await orchestrator.dispose();
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to dispose auto-update orchestrator during shutdown',
        name: 'app_shutdown_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> disconnectHubTransport() async {
    if (_hubConnectionShutdownRegistry.hasBoundPort) {
      try {
        await _hubConnectionShutdownRegistry.disconnectForShutdown();
        return;
      } on Object catch (error, stackTrace) {
        developer.log(
          'Hub connection shutdown port failed; falling back to transport disconnect',
          name: 'app_shutdown_coordinator',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final transport = _transportClient;
    if (transport == null) {
      return;
    }
    await transport.disconnect();
  }
}
