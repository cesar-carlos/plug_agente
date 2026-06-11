import 'dart:math';

import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_access_token_renewer.dart';
import 'package:plug_agente/application/services/hub_connection_session_orchestrator.dart';
import 'package:plug_agente/application/services/hub_hard_relogin_executor.dart';
import 'package:plug_agente/application/services/hub_manual_reconnection_coordinator.dart';
import 'package:plug_agente/application/services/hub_persistent_retry_coordinator.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_runner.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_scheduler.dart';
import 'package:plug_agente/application/services/hub_reconnect_attempt_coordinator.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/services/hub_token_expiry_recovery_coordinator.dart';
import 'package:plug_agente/application/services/hub_transport_lifecycle_coordinator.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/presentation/adapters/presentation_connection_context_source.dart';
import 'package:plug_agente/presentation/presentation.dart' show ConnectionProvider;
import 'package:plug_agente/presentation/providers/connection_display_state.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart' show ConnectionProvider;
import 'package:plug_agente/presentation/providers/providers.dart' show ConnectionProvider;

/// Hub recovery coordinators wired for [ConnectionProvider].
final class ConnectionProviderCoordinatorBundle {
  ConnectionProviderCoordinatorBundle({
    required this.resilienceCoordinator,
    required this.hubRecoveryOrchestrator,
    required this.proactiveTokenRefreshRunner,
    required this.tokenExpiryRecoveryCoordinator,
    required this.manualReconnectionCoordinator,
    required this.persistentRetryCoordinator,
    required this.proactiveTokenRefreshScheduler,
    required this.hubTransportLifecycleCoordinator,
    required this.reconnectAttemptCoordinator,
    required this.hardReloginExecutor,
    required this.connectionSessionOrchestrator,
  });

  final HubResilienceCoordinator resilienceCoordinator;
  final HubRecoveryOrchestrator hubRecoveryOrchestrator;
  final HubProactiveTokenRefreshRunner proactiveTokenRefreshRunner;
  final HubTokenExpiryRecoveryCoordinator tokenExpiryRecoveryCoordinator;
  final HubManualReconnectionCoordinator manualReconnectionCoordinator;
  final HubPersistentRetryCoordinator persistentRetryCoordinator;
  final HubProactiveTokenRefreshScheduler proactiveTokenRefreshScheduler;
  final HubTransportLifecycleCoordinator hubTransportLifecycleCoordinator;
  final HubReconnectAttemptCoordinator reconnectAttemptCoordinator;
  final HubHardReloginExecutor hardReloginExecutor;
  final HubConnectionSessionOrchestrator connectionSessionOrchestrator;
}

/// External dependencies and mutable presentation state for coordinator assembly.
final class ConnectionProviderCoordinatorAssemblyInput {
  ConnectionProviderCoordinatorAssemblyInput({
    required this.connectToHubUseCase,
    required this.transportClient,
    required this.checkHubAvailabilityUseCase,
    required this.contextSource,
    required this.hubRecoveryAuthBridge,
    required this.hubAccessTokenRefreshGate,
    required this.hubAccessTokenRenewer,
    required this.displayState,
    required this.connectionTrackingState,
    required this.uiSink,
    required this.isDisconnectRequested,
    required this.setDisconnectRequested,
    required this.reconnectQuietFailureLogCount,
    required this.setReconnectQuietFailureLogCount,
    required this.resetReconnectQuietFailureLogCount,
    required this.bumpReconnectQuietFailureLogCount,
    required this.notifyStateChanged,
    required this.onNegotiatingWatchdogTimeoutWithoutContext,
    required this.onNegotiatingWatchdogTimeoutWithContext,
    required this.resolveProactiveRefreshAccessToken,
    required this.resolveAuthProviderError,
    required this.normalizeToken,
    required this.initialReconnectDelay,
    required this.maxReconnectDelay,
    required this.tokenRefreshIntervalAttempts,
    required this.maxReconnectAttempts,
    required this.effectiveHardReloginRecoveryEnabled,
    required this.effectiveHardReloginFailureThreshold,
    required this.effectiveHubPersistentRetryMaxFailedTicks,
    required this.effectiveHubPersistentRetryInterval,
    required this.effectiveHubHardReloginCooldown,
    required this.hasAuthBridge,
    this.random,
    this.capabilitiesNegotiationWatchdogOverride,
  });

  final ConnectToHub connectToHubUseCase;
  final ITransportClient transportClient;
  final CheckHubAvailability? checkHubAvailabilityUseCase;
  final IConnectionContextSource contextSource;
  final IHubRecoveryAuthBridge? hubRecoveryAuthBridge;
  final HubAccessTokenRefreshGate hubAccessTokenRefreshGate;
  final HubAccessTokenRenewer? hubAccessTokenRenewer;
  final ConnectionDisplayState displayState;
  final HubConnectionTrackingState connectionTrackingState;
  final HubRecoveryUiSink uiSink;
  final bool Function() isDisconnectRequested;
  final void Function(bool requested) setDisconnectRequested;
  final int Function() reconnectQuietFailureLogCount;
  final void Function(int count) setReconnectQuietFailureLogCount;
  final void Function() resetReconnectQuietFailureLogCount;
  final int Function() bumpReconnectQuietFailureLogCount;
  final void Function() notifyStateChanged;
  final void Function({required int timeoutMs}) onNegotiatingWatchdogTimeoutWithoutContext;
  final void Function() onNegotiatingWatchdogTimeoutWithContext;
  final String? Function() resolveProactiveRefreshAccessToken;
  final String? Function() resolveAuthProviderError;
  final String? Function(String? token) normalizeToken;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;
  final int tokenRefreshIntervalAttempts;
  final int maxReconnectAttempts;
  final bool effectiveHardReloginRecoveryEnabled;
  final int effectiveHardReloginFailureThreshold;
  final int effectiveHubPersistentRetryMaxFailedTicks;
  final Duration effectiveHubPersistentRetryInterval;
  final Duration effectiveHubHardReloginCooldown;
  final bool hasAuthBridge;
  final Random? random;
  final Duration? capabilitiesNegotiationWatchdogOverride;
}

/// Mutable coordinator references shared across assembly steps.
final class ConnectionProviderCoordinatorAssemblyScratch {
  late HubResilienceCoordinator resilienceCoordinator;
  late HubPersistentRetryCoordinator persistentRetryCoordinator;
  late HubRecoveryOrchestrator hubRecoveryOrchestrator;
  late HubConnectionSessionOrchestrator connectionSessionOrchestrator;
  late HubProactiveTokenRefreshScheduler proactiveTokenRefreshScheduler;
  late HubTokenExpiryRecoveryCoordinator tokenExpiryRecoveryCoordinator;
  late HubTransportLifecycleCoordinator hubTransportLifecycleCoordinator;
  late HubManualReconnectionCoordinator manualReconnectionCoordinator;
  late HubReconnectAttemptCoordinator reconnectAttemptCoordinator;
  late HubProactiveTokenRefreshRunner proactiveTokenRefreshRunner;
  late HubHardReloginExecutor hardReloginExecutor;
}

typedef ConnectionProviderResilienceLogPrefix = String Function();
typedef ConnectionProviderTryRefreshToken = Future<TokenRefreshResult> Function(HubConnectionContext context);
typedef ConnectionProviderBurstRecoveryRunner =
    Future<bool> Function(
      HubConnectionContext context, {
      bool proactiveHardReloginBeforeSocket,
    });
