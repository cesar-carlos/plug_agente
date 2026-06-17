import 'dart:async';

import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_coordinator_types.dart';
import 'package:plug_agente/application/services/hub_connection_session_orchestrator.dart';
import 'package:plug_agente/application/services/hub_persistent_retry_coordinator.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_scheduler.dart';
import 'package:plug_agente/application/services/hub_token_expiry_recovery_coordinator.dart';
import 'package:plug_agente/application/services/hub_transport_lifecycle_coordinator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';

void assembleHubConnectionSessionCoordinators({
  required HubConnectionCoordinatorAssemblyInput input,
  required HubConnectionCoordinatorAssemblyScratch scratch,
  required HubConnectionResilienceLogPrefix logResiliencePrefix,
  required void Function() enterNegotiatingState,
  required void Function({required String trigger}) kickHubTransportRecovery,
  required void Function() cancelPersistentRetryTimer,
  required void Function() startPersistentRetry,
  required void Function() startProactiveTokenRefreshSchedule,
  required void Function() cancelProactiveTokenRefreshSchedule,
  required Future<void> Function() disconnectTransportForRecovery,
  required HubConnectionTryRefreshToken tryRefreshToken,
  required HubConnectionBurstRecoveryRunner runBurstRecoveryForContext,
}) {
  scratch.connectionSessionOrchestrator = HubConnectionSessionOrchestrator(
    runtime: HubConnectionSessionRuntimeDependencies(
      connectToHubUseCase: input.connectToHubUseCase,
      transportClient: input.transportClient,
      resilienceCoordinator: scratch.resilienceCoordinator,
      hubRecoveryOrchestrator: scratch.hubRecoveryOrchestrator,
      contextSource: input.contextSource,
      resilienceLogPrefix: logResiliencePrefix,
      isDisconnectRequested: input.isDisconnectRequested,
      setDisconnectRequested: input.setDisconnectRequested,
      clearHubRecoveryUiHint: input.uiSink.clearHubRecoveryUiHint,
      notifyStateChanged: input.notifyStateChanged,
      cancelPersistentRetryTimer: cancelPersistentRetryTimer,
      startPersistentRetry: startPersistentRetry,
      enterNegotiatingState: enterNegotiatingState,
      resetReconnectQuietFailureLogCount: input.resetReconnectQuietFailureLogCount,
      cancelProactiveTokenRefreshSchedule: cancelProactiveTokenRefreshSchedule,
      clearHubAccessTokenRenewerAuthBridge: () => input.hubAccessTokenRenewer?.clearAuthBridge(),
      handleTokenExpired: () => scratch.tokenExpiryRecoveryCoordinator.handleTokenExpired(),
      scheduleExclusiveRecovery: scratch.resilienceCoordinator.scheduleExclusiveRecovery,
      handleHubLifecycle: (notification) => scratch.hubTransportLifecycleCoordinator.handle(notification),
      prepareConnectSession: ({required serverUrl, required agentId, required configId, authToken}) {
        if (input.connectionTrackingState.lastConfigId != null &&
            input.connectionTrackingState.lastConfigId != configId) {
          input.connectionTrackingState.lastAuthToken = null;
        }
        input.connectionTrackingState.lastConfigId = configId;
        input.connectionTrackingState.lastServerUrl = serverUrl;
        input.connectionTrackingState.lastAgentId = agentId;
        input.connectionTrackingState.lastAuthToken =
            input.normalizeToken(authToken) ?? input.connectionTrackingState.lastAuthToken;
      },
      preparePersistentRecoverySession: ({required configId, required serverUrl, required agentId, authToken}) {
        input.connectionTrackingState.lastConfigId = configId;
        input.connectionTrackingState.lastServerUrl = serverUrl;
        input.connectionTrackingState.lastAgentId = agentId;
        input.connectionTrackingState.lastAuthToken = input.normalizeToken(authToken);
      },
      resetSessionAuthInvalid: () => input.connectionTrackingState.sessionAuthInvalid = false,
      clearTrackedAuthToken: () => input.connectionTrackingState.lastAuthToken = null,
      beginConnecting: () {
        input.displayState.status = ConnectionStatus.connecting;
        input.displayState.error = '';
      },
      enterDisconnected: ({bool clearError = false}) {
        input.displayState.status = ConnectionStatus.disconnected;
        if (clearError) {
          input.displayState.error = '';
        }
      },
      enterReconnecting: ({required bool clearError}) {
        input.displayState.status = ConnectionStatus.reconnecting;
        if (clearError) {
          input.displayState.error = '';
        }
      },
      onConnectFailure: (message) {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = message;
      },
      isRecoveryAlreadyInProgress: () =>
          input.displayState.isReconnecting || input.displayState.status == ConnectionStatus.reconnecting,
    ),
  );

  scratch.tokenExpiryRecoveryCoordinator = HubTokenExpiryRecoveryCoordinator(
    runtime: HubTokenExpiryRecoveryRuntimeDependencies(
      resilienceCoordinator: scratch.resilienceCoordinator,
      resilienceLogPrefix: logResiliencePrefix,
      isDisconnectRequested: input.isDisconnectRequested,
      isInternalReconnecting: () => input.displayState.isReconnecting,
      resolveConnectionContext: input.contextSource.resolveConnectionContext,
      tryRefreshToken: tryRefreshToken,
      disconnectTransport: disconnectTransportForRecovery,
      reconfigureTransportCallbacks: scratch.connectionSessionOrchestrator.configureTransportCallbacks,
      attemptReconnect: scratch.reconnectAttemptCoordinator.attemptReconnect,
      recoverConnection: runBurstRecoveryForContext,
      startPersistentRetry: startPersistentRetry,
      beginTokenExpiryRecovery: () {
        input.displayState.isReconnecting = true;
        scratch.hubRecoveryOrchestrator.resetHardReloginCycle();
        input.displayState.status = ConnectionStatus.reconnecting;
        input.displayState.error = '';
      },
      endTokenExpiryRecovery: () {
        input.displayState.isReconnecting = false;
      },
      onMissingConnectionContextForTokenRefresh: () {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = 'Connection context unavailable for token refresh';
        input.uiSink.clearHubRecoveryUiHint();
      },
      onTokenRefreshFailed: () {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = 'Failed to refresh authentication token';
        input.uiSink.clearHubRecoveryUiHint();
      },
      onTokenRefreshException: (message) {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = message;
      },
      clearHubRecoveryUiHint: input.uiSink.clearHubRecoveryUiHint,
      notifyStateChanged: input.notifyStateChanged,
    ),
    proactiveRefreshRunner: scratch.proactiveTokenRefreshRunner,
  );

  scratch.persistentRetryCoordinator = HubPersistentRetryCoordinator(
    runtime: HubPersistentRetryRuntimeDependencies(
      resilienceLogPrefix: logResiliencePrefix,
      maxFailedTicks: input.effectiveHubPersistentRetryMaxFailedTicks,
      resolveConnectionContext: input.contextSource.resolveConnectionContext,
      runPersistentTick: () => scratch.hubRecoveryOrchestrator.runPersistentTick(
        tokenRefreshIntervalAttempts: input.tokenRefreshIntervalAttempts,
        recoveryEnabled: input.effectiveHardReloginRecoveryEnabled,
        hardReloginFailureThreshold: input.effectiveHardReloginFailureThreshold,
      ),
      resetPersistentRetryCounters: scratch.hubRecoveryOrchestrator.resetPersistentRetryCounters,
      onPersistentRetryExhausted: (context, failureCount) {
        input.displayState.status = ConnectionStatus.error;
        input.displayState.error = ConnectionConstants.hubPersistentRetryExhaustedMessage;
        AppLogger.warning(
          'resilience: ${logResiliencePrefix()}persistent_retry event=exhausted '
          'failures=$failureCount '
          'max=${input.effectiveHubPersistentRetryMaxFailedTicks} '
          'agent_id=${context.agentId}',
        );
        scratch.resilienceCoordinator.clearResilienceRecovery();
        input.uiSink.clearHubRecoveryUiHint();
        input.notifyStateChanged();
      },
    ),
  );

  scratch.proactiveTokenRefreshScheduler = HubProactiveTokenRefreshScheduler(
    refreshBeforeExpiry: ConnectionConstants.hubAccessTokenProactiveRefreshMargin,
    accessTokenProvider: input.resolveProactiveRefreshAccessToken,
    onRefreshDue: scratch.proactiveTokenRefreshRunner.run,
  );

  scratch.hubTransportLifecycleCoordinator = HubTransportLifecycleCoordinator(
    runtime: HubTransportLifecycleRuntimeDependencies(
      resilienceCoordinator: scratch.resilienceCoordinator,
      uiSink: input.uiSink,
      resilienceLogPrefix: logResiliencePrefix,
      lastAgentId: () => input.connectionTrackingState.lastAgentId,
      connectionStatusName: () => input.displayState.status.name,
      isDisconnectRequested: input.isDisconnectRequested,
      isDisconnected: () => input.displayState.status == ConnectionStatus.disconnected,
      isNegotiating: () => input.displayState.status == ConnectionStatus.negotiating,
      isReconnecting: () => input.displayState.isReconnectingEffective,
      isConnected: () => input.displayState.isConnected,
      isConnectedOrNegotiating: () =>
          input.displayState.status == ConnectionStatus.connected ||
          input.displayState.status == ConnectionStatus.negotiating,
      hasPersistentRetryTimer: () => scratch.persistentRetryCoordinator.hasActiveTimer,
      persistentRetryInFlight: () => scratch.persistentRetryCoordinator.retryInFlight,
      enterReconnecting: ({required bool clearError}) {
        input.displayState.status = ConnectionStatus.reconnecting;
        if (clearError) {
          input.displayState.error = '';
        }
        input.notifyStateChanged();
      },
      enterConnected: () {
        input.displayState.status = ConnectionStatus.connected;
        input.displayState.isReconnecting = false;
        input.displayState.error = '';
        input.notifyStateChanged();
      },
      kickHubTransportRecovery: kickHubTransportRecovery,
      schedulePersistentRetryTick: () => unawaited(scratch.persistentRetryCoordinator.tick()),
      cancelPersistentRetryTimer: cancelPersistentRetryTimer,
      startProactiveTokenRefreshSchedule: startProactiveTokenRefreshSchedule,
    ),
  );
}
