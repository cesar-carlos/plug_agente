import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

/// Handles explicit hub reconnection requests after transport recovery signals.
final class HubManualReconnectionCoordinator {
  HubManualReconnectionCoordinator({
    required HubManualReconnectionRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubManualReconnectionRuntimeDependencies _deps;

  Future<void> handleReconnectionNeeded() async {
    if (_deps.isInternalReconnecting() || _deps.isDisconnectRequested()) {
      AppLogger.debug(
        'resilience: ${_deps.resilienceLogPrefix()}reconnect event=handler_skipped '
        'reconnecting=${_deps.isInternalReconnecting()} disconnect_requested=${_deps.isDisconnectRequested()}',
      );
      return;
    }

    _deps.beginManualReconnection();
    AppLogger.warning('Reconnection needed after failed attempts');
    _deps.notifyStateChanged();

    try {
      final context = _deps.resolveConnectionContext();
      if (context == null) {
        _deps.onMissingConnectionContextForReconnection();
        AppLogger.error('Missing server URL or agent ID for reconnection');
      } else {
        _deps.resilienceCoordinator.beginResilienceRecovery();
        AppLogger.info(
          'resilience: ${_deps.resilienceLogPrefix()}reconnect event=full_recovery_started '
          'agent_id=${context.agentId}',
        );
        final connected = await _deps.recoverConnection(context);
        if (_deps.isDisconnectRequested()) {
          _deps.onDisconnectDuringReconnection();
          _deps.resilienceCoordinator.clearResilienceRecovery();
          return;
        }
        if (connected) {
          AppLogger.info(
            'resilience: ${_deps.resilienceLogPrefix()}reconnect event=burst_recovery_complete '
            'agent_id=${context.agentId}',
          );
        }
        if (!connected) {
          if (_deps.isDisconnectRequested()) {
            _deps.resilienceCoordinator.clearResilienceRecovery();
            return;
          }
          _deps.onBurstRecoveryExhausted();
          AppLogger.warning('Connection burst recovery exhausted; starting persistent hub retry');
          _deps.startPersistentRetry();
        }
      }
    } on Exception catch (error, stackTrace) {
      _deps.resilienceCoordinator.clearResilienceRecovery();
      _deps.clearHubRecoveryUiHint();
      final failure = domain_errors.ConnectionFailure.withContext(
        message: 'Failed to reconnect to the hub',
        cause: error,
        context: {'operation': 'handleReconnectionNeeded'},
      );
      _deps.onReconnectionException(failure.toDisplayMessage());
      AppLogger.error(
        'Manual reconnection failed: ${failure.toDisplayMessage()}',
        error,
        stackTrace,
      );
    } finally {
      _deps.endManualReconnection();
      _deps.notifyStateChanged();
    }
  }
}

final class HubManualReconnectionRuntimeDependencies {
  HubManualReconnectionRuntimeDependencies({
    required this.resilienceCoordinator,
    required this.resilienceLogPrefix,
    required this.isDisconnectRequested,
    required this.isInternalReconnecting,
    required this.resolveConnectionContext,
    required this.recoverConnection,
    required this.startPersistentRetry,
    required this.beginManualReconnection,
    required this.endManualReconnection,
    required this.onMissingConnectionContextForReconnection,
    required this.onDisconnectDuringReconnection,
    required this.onBurstRecoveryExhausted,
    required this.onReconnectionException,
    required this.clearHubRecoveryUiHint,
    required this.notifyStateChanged,
  });

  final HubResilienceCoordinator resilienceCoordinator;
  final String Function() resilienceLogPrefix;
  final bool Function() isDisconnectRequested;
  final bool Function() isInternalReconnecting;
  final HubConnectionContext? Function() resolveConnectionContext;
  final Future<bool> Function(HubConnectionContext context) recoverConnection;
  final void Function() startPersistentRetry;
  final void Function() beginManualReconnection;
  final void Function() endManualReconnection;
  final void Function() onMissingConnectionContextForReconnection;
  final void Function() onDisconnectDuringReconnection;
  final void Function() onBurstRecoveryExhausted;
  final void Function(String message) onReconnectionException;
  final void Function() clearHubRecoveryUiHint;
  final void Function() notifyStateChanged;
}
