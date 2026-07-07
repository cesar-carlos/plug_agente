import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:result_dart/result_dart.dart';

/// Orchestrates hub connect/disconnect session setup without Flutter widgets.
final class HubConnectionSessionOrchestrator {
  HubConnectionSessionOrchestrator({
    required HubConnectionSessionRuntimeDependencies runtime,
  }) : _deps = runtime;

  final HubConnectionSessionRuntimeDependencies _deps;

  Future<Result<void>> connect(
    String serverUrl,
    String agentId, {
    String? configId,
    String? authToken,
    bool recoverOnFailure = false,
  }) async {
    _deps.cancelPersistentRetryTimer();
    _deps.hubRecoveryOrchestrator.resetForUserConnect();
    _deps.resetSessionAuthInvalid();
    _deps.resilienceCoordinator.resetAuthRecoveryState();
    _deps.resetReconnectQuietFailureLogCount();
    _deps.resilienceCoordinator.invalidateHubConnectEpoch();
    _deps.resilienceCoordinator.clearResilienceRecovery();
    _deps.clearHubRecoveryUiHint();
    _deps.setDisconnectRequested(false);
    _deps.prepareConnectSession(
      serverUrl: serverUrl,
      agentId: agentId,
      configId: _deps.contextSource.resolveActiveConfigId(configId),
      authToken: authToken,
    );

    _deps.resilienceCoordinator.cancelNegotiatingWatchdog();
    _deps.beginConnecting();
    _deps.notifyStateChanged();

    _configureTransportCallbacks();

    final result = await _deps.resilienceCoordinator.runSerializedHubConnect(
      () => _deps.connectToHubUseCase(
        serverUrl,
        agentId,
        authToken: authToken,
      ),
      staleResult: Failure(
        domain_errors.ConnectionFailure.withContext(
          message: 'Connection attempt superseded by a newer request',
          context: {'operation': 'connect', 'reason': 'stale_epoch'},
        ),
      ),
    );

    final finalResult = result.fold<Result<void>>(
      (_) {
        if (_deps.isDisconnectRequested()) {
          return const Success(unit);
        }
        _deps.cancelPersistentRetryTimer();
        _deps.clearHubRecoveryUiHint();
        _deps.enterNegotiatingState();
        AppLogger.info('Connected to hub transport; waiting for protocol negotiation');
        return const Success(unit);
      },
      (failure) {
        if (_deps.isDisconnectRequested()) {
          _deps.enterDisconnected();
          return Failure(failure);
        }
        if (_deps.isRecoveryAlreadyInProgress()) {
          AppLogger.warning(
            'Initial connect failure ignored because hub recovery is already in progress: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          return Failure(failure);
        }
        if (recoverOnFailure && _deps.contextSource.resolveConnectionContext() != null) {
          _deps.resilienceCoordinator.beginResilienceRecovery();
          _deps.enterReconnecting(clearError: true);
          _deps.clearHubRecoveryUiHint();
          AppLogger.warning(
            'Initial hub connect failed; entering persistent recovery: ${failure.toDisplayMessage()}',
            failure.toTechnicalMessage(),
          );
          _deps.startPersistentRetry();
          return Failure(failure);
        }
        _deps.onConnectFailure(failure.toDisplayMessage());
        _deps.clearHubRecoveryUiHint();
        AppLogger.error(
          'Failed to connect to hub: ${failure.toDisplayMessage()}',
          failure.toTechnicalMessage(),
        );
        return Failure(failure);
      },
    );

    _deps.notifyStateChanged();
    return finalResult;
  }

  void startPersistentHubRecovery({
    required String configId,
    required String serverUrl,
    required String agentId,
    String? authToken,
  }) {
    _deps.cancelPersistentRetryTimer();
    _deps.hubRecoveryOrchestrator.resetForStartupPersistentRecovery();
    _deps.resetSessionAuthInvalid();
    _deps.resilienceCoordinator.resetAuthRecoveryState();
    _deps.resetReconnectQuietFailureLogCount();
    _deps.setDisconnectRequested(false);
    _deps.preparePersistentRecoverySession(
      configId: configId,
      serverUrl: serverUrl,
      agentId: agentId,
      authToken: authToken,
    );

    _configureTransportCallbacks();
    _deps.resilienceCoordinator.beginResilienceRecovery();
    _deps.enterReconnecting(clearError: true);
    _deps.clearHubRecoveryUiHint();
    AppLogger.warning(
      'resilience: ${_deps.resilienceLogPrefix()}persistent_retry event=startup_recovery_started '
      'agent_id=$agentId',
    );
    _deps.notifyStateChanged();
    _deps.startPersistentRetry();
  }

  Future<void> disconnect() async {
    _deps.setDisconnectRequested(true);
    _deps.clearHubAccessTokenRenewerAuthBridge();
    _deps.resilienceCoordinator.invalidateHubConnectEpoch();
    _deps.resilienceCoordinator.cancelNegotiatingWatchdog();
    _deps.resilienceCoordinator.clearResilienceRecovery();
    _deps.clearHubRecoveryUiHint();
    _deps.cancelPersistentRetryTimer();
    _deps.cancelProactiveTokenRefreshSchedule();
    _deps.hubRecoveryOrchestrator.resetForDisconnect();
    _deps.resilienceCoordinator.resetAuthRecoveryState();
    _deps.resetReconnectQuietFailureLogCount();
    _deps.clearTrackedAuthToken();
    await _deps.transportClient.disconnect();
    _deps.enterDisconnected(clearError: true);
    _deps.notifyStateChanged();

    AppLogger.info('Disconnected from hub');
  }

  void configureTransportCallbacks() => _configureTransportCallbacks();

  void _configureTransportCallbacks() {
    _deps.transportClient.setOnTokenExpired(_deps.handleTokenExpired);
    _deps.transportClient.setOnReconnectionNeeded(_deps.scheduleExclusiveRecovery);
    _deps.transportClient.setOnHubLifecycle(_deps.handleHubLifecycle);
  }
}

final class HubConnectionSessionRuntimeDependencies {
  HubConnectionSessionRuntimeDependencies({
    required this.connectToHubUseCase,
    required this.transportClient,
    required this.resilienceCoordinator,
    required this.hubRecoveryOrchestrator,
    required this.contextSource,
    required this.resilienceLogPrefix,
    required this.isDisconnectRequested,
    required this.setDisconnectRequested,
    required this.clearHubRecoveryUiHint,
    required this.notifyStateChanged,
    required this.cancelPersistentRetryTimer,
    required this.startPersistentRetry,
    required this.enterNegotiatingState,
    required this.resetReconnectQuietFailureLogCount,
    required this.cancelProactiveTokenRefreshSchedule,
    required this.clearHubAccessTokenRenewerAuthBridge,
    required this.handleTokenExpired,
    required this.scheduleExclusiveRecovery,
    required this.handleHubLifecycle,
    required this.prepareConnectSession,
    required this.preparePersistentRecoverySession,
    required this.resetSessionAuthInvalid,
    required this.clearTrackedAuthToken,
    required this.beginConnecting,
    required this.enterDisconnected,
    required this.enterReconnecting,
    required this.onConnectFailure,
    required this.isRecoveryAlreadyInProgress,
  });

  final ConnectToHub connectToHubUseCase;
  final ITransportClient transportClient;
  final HubResilienceCoordinator resilienceCoordinator;
  final HubRecoveryOrchestrator hubRecoveryOrchestrator;
  final IConnectionContextSource contextSource;
  final String Function() resilienceLogPrefix;
  final bool Function() isDisconnectRequested;
  final void Function(bool requested) setDisconnectRequested;
  final void Function() clearHubRecoveryUiHint;
  final void Function() notifyStateChanged;
  final void Function() cancelPersistentRetryTimer;
  final void Function() startPersistentRetry;
  final void Function() enterNegotiatingState;
  final void Function() resetReconnectQuietFailureLogCount;
  final void Function() cancelProactiveTokenRefreshSchedule;
  final void Function() clearHubAccessTokenRenewerAuthBridge;
  final Future<void> Function() handleTokenExpired;
  final Future<void> Function() scheduleExclusiveRecovery;
  final void Function(HubLifecycleNotification notification) handleHubLifecycle;
  final void Function({
    required String serverUrl,
    required String agentId,
    required String configId,
    String? authToken,
  })
  prepareConnectSession;
  final void Function({
    required String configId,
    required String serverUrl,
    required String agentId,
    String? authToken,
  })
  preparePersistentRecoverySession;
  final void Function() resetSessionAuthInvalid;
  final void Function() clearTrackedAuthToken;
  final void Function() beginConnecting;
  final void Function({bool clearError}) enterDisconnected;
  final void Function({required bool clearError}) enterReconnecting;
  final void Function(String message) onConnectFailure;
  final bool Function() isRecoveryAlreadyInProgress;
}
