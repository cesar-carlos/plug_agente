import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';

/// Handles hub transport lifecycle notifications; state mutations are delegated
/// via [HubTransportLifecycleRuntimeDependencies] (same pattern as recovery).
///
/// Ownership: on `client_or_network` disconnect, update UI and let Socket.IO
/// manager reconnect. App-owned burst recovery starts only via
/// `onReconnectionNeeded` (reconnect_failed, heartbeat stale, negotiation
/// failure, post-reconnect register failure) or an immediate kick for
/// `io_server_disconnect` (transport also escalates via `onReconnectionNeeded`;
/// the exclusive recovery gate coalesces any double schedule).
final class HubTransportLifecycleCoordinator {
  HubTransportLifecycleCoordinator({
    required HubTransportLifecycleRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubTransportLifecycleRuntimeDependencies _deps;

  void handle(HubLifecycleNotification notification) {
    if (_deps.isDisconnectRequested()) {
      return;
    }

    switch (notification) {
      case HubTransportDisconnected(:final reason):
        if (_deps.isDisconnected()) {
          return;
        }
        _deps.resilienceCoordinator.beginResilienceRecovery();
        final serverInitiated = isHubIoServerInitiatedDisconnect(reason);
        final disconnectLine =
            'resilience: ${_deps.resilienceLogPrefix()}hub_transport event=socket_disconnected '
            'kind=${serverInitiated ? "io_server_disconnect" : "client_or_network"} '
            'reason=${reason ?? "unknown"} '
            'action=${serverInitiated ? "kick_app_recovery" : "await_socket_io_reconnect"} '
            'agent_id=${_deps.lastAgentId() ?? "?"}';
        AppLogger.debug(disconnectLine);
        _deps.enterReconnecting(clearError: true);
        // Server-forced close: Socket.IO will not auto-reconnect; escalate now.
        // client_or_network: leave L0 Socket.IO manager in charge until it
        // escalates through onReconnectionNeeded (reconnect_failed, etc.).
        if (serverInitiated) {
          _deps.kickHubTransportRecovery(trigger: 'hub_transport_io_server_disconnect');
        }
        if (_deps.hasPersistentRetryTimer() && !_deps.persistentRetryInFlight()) {
          _deps.schedulePersistentRetryTick();
        }
      case HubTransportReconnectAttempt(:final attemptNumber):
        AppLogger.info(
          'resilience: ${_deps.resilienceLogPrefix()}hub_socket_reconnect_attempt attempt=$attemptNumber '
          'status=${_deps.connectionStatusName()}',
        );
        if (_deps.isConnectedOrNegotiating()) {
          _deps.enterReconnecting(clearError: true);
        }
      case HubProtocolReady():
        _handleProtocolReady(eventName: 'protocol_ready');
      case HubTransportAutoReconnectSucceeded():
        _handleProtocolReady(eventName: 'auto_reconnect_capabilities_ok');
    }
  }

  void _handleProtocolReady({required String eventName}) {
    if (!_deps.isNegotiating() && !_deps.isReconnecting() && !_deps.isConnected()) {
      AppLogger.debug(
        'resilience: ${_deps.resilienceLogPrefix()}hub_transport event=${eventName}_ignored '
        'status=${_deps.connectionStatusName()} agent_id=${_deps.lastAgentId() ?? "?"}',
      );
      return;
    }
    AppLogger.info(
      'resilience: ${_deps.resilienceLogPrefix()}hub_transport event=$eventName '
      'agent_id=${_deps.lastAgentId() ?? "?"}',
    );
    _deps.resilienceCoordinator.cancelNegotiatingWatchdog();
    _deps.resilienceCoordinator.clearResilienceRecovery();
    _deps.cancelPersistentRetryTimer();
    _deps.uiSink.clearHubRecoveryUiHint();
    _deps.enterConnected();
    _deps.startProactiveTokenRefreshSchedule();
  }
}

final class HubTransportLifecycleRuntimeDependencies {
  HubTransportLifecycleRuntimeDependencies({
    required this.resilienceCoordinator,
    required this.uiSink,
    required this.resilienceLogPrefix,
    required this.lastAgentId,
    required this.connectionStatusName,
    required this.isDisconnectRequested,
    required this.isDisconnected,
    required this.isNegotiating,
    required this.isReconnecting,
    required this.isConnected,
    required this.isConnectedOrNegotiating,
    required this.hasPersistentRetryTimer,
    required this.persistentRetryInFlight,
    required this.enterReconnecting,
    required this.enterConnected,
    required this.kickHubTransportRecovery,
    required this.schedulePersistentRetryTick,
    required this.cancelPersistentRetryTimer,
    required this.startProactiveTokenRefreshSchedule,
  });

  final HubResilienceCoordinator resilienceCoordinator;
  final HubRecoveryUiSink uiSink;
  final String Function() resilienceLogPrefix;
  final String? Function() lastAgentId;
  final String Function() connectionStatusName;
  final bool Function() isDisconnectRequested;
  final bool Function() isDisconnected;
  final bool Function() isNegotiating;
  final bool Function() isReconnecting;
  final bool Function() isConnected;
  final bool Function() isConnectedOrNegotiating;
  final bool Function() hasPersistentRetryTimer;
  final bool Function() persistentRetryInFlight;
  final void Function({required bool clearError}) enterReconnecting;
  final void Function() enterConnected;
  final void Function({required String trigger}) kickHubTransportRecovery;
  final void Function() schedulePersistentRetryTick;
  final void Function() cancelPersistentRetryTimer;
  final void Function() startProactiveTokenRefreshSchedule;
}
