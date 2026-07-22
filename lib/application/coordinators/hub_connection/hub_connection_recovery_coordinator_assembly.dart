import 'dart:async';

import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_coordinator_types.dart';
import 'package:plug_agente/application/services/hub_hard_relogin_executor.dart';
import 'package:plug_agente/application/services/hub_manual_reconnection_coordinator.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_runner.dart';
import 'package:plug_agente/application/services/hub_reconnect_attempt_coordinator.dart';
import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/core/di/hub_recovery_orchestrator_factory.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

void assembleHubConnectionRecoveryCoordinators({
  required HubConnectionCoordinatorAssemblyInput input,
  required HubConnectionCoordinatorAssemblyScratch scratch,
  required HubConnectionResilienceLogPrefix logResiliencePrefix,
  required void Function() enterNegotiatingState,
  required void Function({required String trigger}) kickHubTransportRecovery,
  required void Function() cancelPersistentRetryTimer,
  required void Function() startPersistentRetry,
  required void Function() startProactiveTokenRefreshSchedule,
  required Future<void> Function() disconnectTransportForRecovery,
  required HubConnectionTryRefreshToken tryRefreshToken,
}) {
  scratch.resilienceCoordinator = HubResilienceCoordinator(
    environment: HubResilienceEnvironment(
      isDisconnectRequested: input.isDisconnectRequested,
      isBurstRecoveryInFlight: () => input.displayState.isBurstRecoveryInFlight,
      hasPersistentRetryTimer: () => scratch.persistentRetryCoordinator.hasActiveTimer,
      persistentRetryInFlight: () => scratch.persistentRetryCoordinator.retryInFlight,
      isNegotiating: () => input.displayState.status == ConnectionStatus.negotiating,
      resolveConnectionContext: input.contextSource.resolveConnectionContext,
      lastAgentId: () => input.connectionTrackingState.lastAgentId,
      syncTransportResilienceLogContext: input.transportClient.setResilienceLogContext,
      handleReconnectionNeeded: () => scratch.manualReconnectionCoordinator.handleReconnectionNeeded(),
      onNegotiatingWatchdogTimeoutWithoutContext: input.onNegotiatingWatchdogTimeoutWithoutContext,
      onNegotiatingWatchdogTimeoutWithContext: input.onNegotiatingWatchdogTimeoutWithContext,
    ),
    connectionContextSource: input.contextSource,
    recoveryAuthBridge: input.hubRecoveryAuthBridge,
    tokenRefreshGate: input.hubAccessTokenRefreshGate,
    capabilitiesNegotiationWatchdogOverride: input.capabilitiesNegotiationWatchdogOverride,
    random: input.random,
  );

  scratch.reconnectAttemptCoordinator = HubReconnectAttemptCoordinator(
    runtime: HubReconnectAttemptRuntimeDependencies(
      connectToHubUseCase: input.connectToHubUseCase,
      resilienceCoordinator: scratch.resilienceCoordinator,
      onTransportConnectSuccessDuringRecovery: () =>
          scratch.hubRecoveryOrchestrator.noteTransportConnectSuccessDuringRecovery(),
      onTransportConnectFailureDuringRecovery: () =>
          scratch.hubRecoveryOrchestrator.noteTransportConnectFailureDuringRecovery(),
      resilienceLogPrefix: logResiliencePrefix,
      isDisconnectRequested: input.isDisconnectRequested,
      isReconnectingUiState: () =>
          input.displayState.status == ConnectionStatus.reconnecting || input.displayState.isBurstRecoveryInFlight,
      cancelPersistentRetryTimer: cancelPersistentRetryTimer,
      onTransportReconnectSuccess: ({required serverUrl, required agentId, authToken}) {
        input.connectionTrackingState.sessionAuthInvalid = false;
        input.setReconnectQuietFailureLogCount(0);
        enterNegotiatingState();
        input.connectionTrackingState.lastServerUrl = serverUrl;
        input.connectionTrackingState.lastAgentId = agentId;
        if (authToken != null && authToken.trim().isNotEmpty) {
          input.connectionTrackingState.lastAuthToken = authToken.trim();
        }
      },
      onTransportReconnectFailure: ({required message}) {
        input.displayState.status = ConnectionStatus.reconnecting;
        input.displayState.error = message;
      },
      resetReconnectQuietFailureLogCount: input.resetReconnectQuietFailureLogCount,
      bumpReconnectQuietFailureLogCount: input.bumpReconnectQuietFailureLogCount,
      setHubRecoveryUiHint: input.uiSink.setHubRecoveryUiHint,
      clearHubRecoveryUiHint: input.uiSink.clearHubRecoveryUiHint,
    ),
  );

  scratch.hardReloginExecutor = HubHardReloginExecutor(
    runtime: HubHardReloginRuntimeDependencies(
      resilienceCoordinator: scratch.resilienceCoordinator,
      hardReloginCooldown: input.effectiveHubHardReloginCooldown,
      setHubRecoveryUiHint: input.uiSink.setHubRecoveryUiHint,
      clearHubRecoveryUiHint: input.uiSink.clearHubRecoveryUiHint,
      cancelPersistentRetryTimer: cancelPersistentRetryTimer,
      onAuthBridgeUnavailable: () {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = 'Authentication provider unavailable for automatic relogin';
      },
      onHardReloginFailed: (message) {
        input.connectionTrackingState.lastAuthToken = null;
        input.connectionTrackingState.sessionAuthInvalid = true;
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = message;
      },
      onHardReloginSuccess: (token) {
        input.connectionTrackingState.sessionAuthInvalid = false;
        scratch.hubRecoveryOrchestrator.resetConsecutiveFailuresAfterHardReloginSuccess();
        return input.connectionTrackingState.lastAuthToken = token;
      },
    ),
  );

  scratch.hubRecoveryOrchestrator = createHubRecoveryOrchestrator(
    initialReconnectDelay: input.initialReconnectDelay,
    maxReconnectDelay: input.maxReconnectDelay,
    random: input.random,
    runtime: HubRecoveryRuntimeDependencies(
      resilienceCoordinator: scratch.resilienceCoordinator,
      contextSource: input.contextSource,
      checkHubAvailability: input.checkHubAvailabilityUseCase,
      uiSink: input.uiSink,
      resilienceLogPrefix: logResiliencePrefix,
      isDisconnectRequested: input.isDisconnectRequested,
      tryRefreshToken: tryRefreshToken,
      attemptReconnect: scratch.reconnectAttemptCoordinator.attemptReconnect,
      disconnectTransportForRecovery: disconnectTransportForRecovery,
      executeHardRelogin: scratch.hardReloginExecutor.execute,
      bumpPersistentReconnectFailure: (context, {required reason}) {
        scratch.persistentRetryCoordinator.bumpPersistentReconnectFailure(
          context,
          reason: reason,
          orchestrator: scratch.hubRecoveryOrchestrator,
        );
      },
      isStatusError: () => input.displayState.status == ConnectionStatus.error,
      cancelPersistentRetryTimer: cancelPersistentRetryTimer,
    ),
  );

  scratch.proactiveTokenRefreshRunner = HubProactiveTokenRefreshRunner(
    runtime: HubProactiveTokenRefreshRuntimeDependencies(
      tokenRefreshGate: input.hubAccessTokenRefreshGate,
      isDisconnectRequested: input.isDisconnectRequested,
      isConnected: () => input.displayState.isConnected,
      isSessionAuthInvalid: () => input.connectionTrackingState.sessionAuthInvalid,
      resolveConnectionContext: input.contextSource.resolveConnectionContext,
      resolveAuthTokenForReconnect: input.contextSource.resolveAuthTokenForReconnect,
      tryRefreshToken: tryRefreshToken,
      disconnectTransport: disconnectTransportForRecovery,
      attemptReconnect: scratch.reconnectAttemptCoordinator.attemptReconnect,
      kickHubTransportRecovery: kickHubTransportRecovery,
      onTerminalRefreshFailure: () {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = input.hubRecoveryAuthBridge == null
            ? 'Failed to refresh authentication token'
            : input.resolveAuthProviderError() ?? 'Failed to refresh authentication token';
        input.notifyStateChanged();
      },
      rescheduleProactiveRefresh: startProactiveTokenRefreshSchedule,
    ),
  );

  scratch.manualReconnectionCoordinator = HubManualReconnectionCoordinator(
    runtime: HubManualReconnectionRuntimeDependencies(
      resilienceCoordinator: scratch.resilienceCoordinator,
      resilienceLogPrefix: logResiliencePrefix,
      isDisconnectRequested: input.isDisconnectRequested,
      isInternalReconnecting: () => input.displayState.isBurstRecoveryInFlight,
      resolveConnectionContext: input.contextSource.resolveConnectionContext,
      recoverConnection: (context, {bool proactiveHardReloginBeforeSocket = false}) =>
          scratch.hubRecoveryOrchestrator.runBurstRecovery(
            context,
            proactiveHardReloginBeforeSocket: proactiveHardReloginBeforeSocket,
            effectiveHardReloginRecoveryEnabled: input.effectiveHardReloginRecoveryEnabled,
            hasAuthBridge: input.hasAuthBridge,
            maxReconnectAttempts: input.maxReconnectAttempts,
            tokenRefreshIntervalAttempts: input.tokenRefreshIntervalAttempts,
            recoveryEnabled: input.effectiveHardReloginRecoveryEnabled,
            hardReloginFailureThreshold: input.effectiveHardReloginFailureThreshold,
          ),
      startPersistentRetry: startPersistentRetry,
      beginManualReconnection: () {
        input.displayState.isBurstRecoveryInFlight = true;
        scratch.hubRecoveryOrchestrator.resetHardReloginCycle();
        input.displayState.status = ConnectionStatus.reconnecting;
        input.displayState.error = '';
      },
      endManualReconnection: () {
        input.displayState.isBurstRecoveryInFlight = false;
      },
      onMissingConnectionContextForReconnection: () {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = 'Server URL or Agent ID not available for reconnection';
        input.uiSink.clearHubRecoveryUiHint();
      },
      onDisconnectDuringReconnection: () {
        input.displayState.status = ConnectionStatus.disconnected;
        input.displayState.error = '';
        AppLogger.info('Reconnection loop cancelled by user disconnect');
      },
      onBurstRecoveryExhausted: () {
        input.displayState.status = ConnectionStatus.reconnecting;
        input.displayState.error = '';
      },
      onReconnectionException: (message) {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = message;
      },
      clearHubRecoveryUiHint: input.uiSink.clearHubRecoveryUiHint,
      notifyStateChanged: input.notifyStateChanged,
    ),
  );
}

Future<void> disconnectTransportForHubConnectionRecovery({
  required ITransportClient transportClient,
  required HubConnectionResilienceLogPrefix logResiliencePrefix,
  required void Function() reconfigureTransportCallbacks,
}) async {
  try {
    final result = await transportClient.disconnect();
    result.fold(
      (_) {},
      (failure) {
        AppLogger.warning(
          'resilience: ${logResiliencePrefix()}transport_disconnect_during_recovery message=$failure',
        );
      },
    );
  } on Object catch (error, stackTrace) {
    AppLogger.warning(
      'resilience: ${logResiliencePrefix()}transport_disconnect_during_recovery event=exception',
      error,
      stackTrace,
    );
  } finally {
    reconfigureTransportCallbacks();
  }
}

Future<TokenRefreshResult> tryRefreshHubConnectionToken({
  required HubResilienceCoordinator resilienceCoordinator,
  required HubConnectionCoordinatorAssemblyInput input,
  required void Function() startProactiveTokenRefreshSchedule,
  required HubConnectionContext context,
}) async {
  final result = await resilienceCoordinator.tryRefreshToken(context);
  switch (result.kind) {
    case TokenRefreshResultKind.refreshed:
      input.connectionTrackingState.sessionAuthInvalid = false;
      input.connectionTrackingState.lastAuthToken = result.token;
      if (!input.isDisconnectRequested() && input.displayState.isConnected) {
        startProactiveTokenRefreshSchedule();
      }
    case TokenRefreshResultKind.terminalFailure:
      input.connectionTrackingState.lastAuthToken = null;
      input.connectionTrackingState.sessionAuthInvalid = true;
    case TokenRefreshResultKind.skippedByCooldown:
    case TokenRefreshResultKind.transientFailure:
      break;
  }
  return result;
}
