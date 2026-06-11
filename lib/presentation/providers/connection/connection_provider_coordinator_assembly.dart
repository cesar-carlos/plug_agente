import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/presentation/providers/connection/connection_provider_coordinator_types.dart';
import 'package:plug_agente/presentation/providers/connection/connection_provider_recovery_coordinator_assembly.dart';
import 'package:plug_agente/presentation/providers/connection/connection_provider_session_coordinator_assembly.dart';
import 'package:plug_agente/presentation/providers/connection_display_state.dart';

export 'connection_provider_coordinator_types.dart';

ConnectionProviderCoordinatorBundle assembleConnectionProviderCoordinators(
  ConnectionProviderCoordinatorAssemblyInput input,
) {
  final scratch = ConnectionProviderCoordinatorAssemblyScratch();

  void enterNegotiatingState() {
    input.displayState.status = ConnectionStatus.negotiating;
    input.displayState.error = '';
    scratch.resilienceCoordinator.armNegotiatingWatchdog();
  }

  String logResiliencePrefix() => scratch.resilienceCoordinator.resilienceLogPrefix();

  void kickHubTransportRecovery({required String trigger}) {
    scratch.resilienceCoordinator.kickHubTransportRecovery(trigger: trigger);
  }

  void cancelPersistentRetryTimer() {
    scratch.persistentRetryCoordinator.cancelTimer();
  }

  void startPersistentRetry() {
    scratch.persistentRetryCoordinator.start(interval: input.effectiveHubPersistentRetryInterval);
  }

  void startProactiveTokenRefreshSchedule() {
    scratch.proactiveTokenRefreshScheduler.reschedule();
  }

  void cancelProactiveTokenRefreshSchedule() {
    scratch.proactiveTokenRefreshScheduler.cancel();
  }

  Future<void> disconnectTransportForRecovery() => disconnectTransportForConnectionProviderRecovery(
    transportClient: input.transportClient,
    logResiliencePrefix: logResiliencePrefix,
    reconfigureTransportCallbacks: scratch.connectionSessionOrchestrator.configureTransportCallbacks,
  );

  Future<TokenRefreshResult> tryRefreshToken(HubConnectionContext context) => tryRefreshConnectionProviderToken(
    resilienceCoordinator: scratch.resilienceCoordinator,
    input: input,
    startProactiveTokenRefreshSchedule: startProactiveTokenRefreshSchedule,
    context: context,
  );

  Future<bool> runBurstRecoveryForContext(
    HubConnectionContext context, {
    bool proactiveHardReloginBeforeSocket = false,
  }) {
    return scratch.hubRecoveryOrchestrator.runBurstRecovery(
      context,
      proactiveHardReloginBeforeSocket: proactiveHardReloginBeforeSocket,
      effectiveHardReloginRecoveryEnabled: input.effectiveHardReloginRecoveryEnabled,
      hasAuthBridge: input.hasAuthBridge,
      maxReconnectAttempts: input.maxReconnectAttempts,
      tokenRefreshIntervalAttempts: input.tokenRefreshIntervalAttempts,
      recoveryEnabled: input.effectiveHardReloginRecoveryEnabled,
      hardReloginFailureThreshold: input.effectiveHardReloginFailureThreshold,
    );
  }

  assembleConnectionProviderRecoveryCoordinators(
    input: input,
    scratch: scratch,
    logResiliencePrefix: logResiliencePrefix,
    enterNegotiatingState: enterNegotiatingState,
    kickHubTransportRecovery: kickHubTransportRecovery,
    cancelPersistentRetryTimer: cancelPersistentRetryTimer,
    startPersistentRetry: startPersistentRetry,
    startProactiveTokenRefreshSchedule: startProactiveTokenRefreshSchedule,
    disconnectTransportForRecovery: disconnectTransportForRecovery,
    tryRefreshToken: tryRefreshToken,
  );

  assembleConnectionProviderSessionCoordinators(
    input: input,
    scratch: scratch,
    logResiliencePrefix: logResiliencePrefix,
    enterNegotiatingState: enterNegotiatingState,
    kickHubTransportRecovery: kickHubTransportRecovery,
    cancelPersistentRetryTimer: cancelPersistentRetryTimer,
    startPersistentRetry: startPersistentRetry,
    startProactiveTokenRefreshSchedule: startProactiveTokenRefreshSchedule,
    cancelProactiveTokenRefreshSchedule: cancelProactiveTokenRefreshSchedule,
    disconnectTransportForRecovery: disconnectTransportForRecovery,
    tryRefreshToken: tryRefreshToken,
    runBurstRecoveryForContext: runBurstRecoveryForContext,
  );

  return ConnectionProviderCoordinatorBundle(
    resilienceCoordinator: scratch.resilienceCoordinator,
    hubRecoveryOrchestrator: scratch.hubRecoveryOrchestrator,
    proactiveTokenRefreshRunner: scratch.proactiveTokenRefreshRunner,
    tokenExpiryRecoveryCoordinator: scratch.tokenExpiryRecoveryCoordinator,
    manualReconnectionCoordinator: scratch.manualReconnectionCoordinator,
    persistentRetryCoordinator: scratch.persistentRetryCoordinator,
    proactiveTokenRefreshScheduler: scratch.proactiveTokenRefreshScheduler,
    hubTransportLifecycleCoordinator: scratch.hubTransportLifecycleCoordinator,
    reconnectAttemptCoordinator: scratch.reconnectAttemptCoordinator,
    hardReloginExecutor: scratch.hardReloginExecutor,
    connectionSessionOrchestrator: scratch.connectionSessionOrchestrator,
  );
}
