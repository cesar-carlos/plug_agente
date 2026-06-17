import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_coordinator_types.dart';
import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_recovery_coordinator_assembly.dart';
import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_session_coordinator_assembly.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

export 'hub_connection_coordinator_types.dart';

HubConnectionCoordinatorBundle assembleHubConnectionCoordinators(
  HubConnectionCoordinatorAssemblyInput input,
) {
  final scratch = HubConnectionCoordinatorAssemblyScratch();

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

  Future<void> disconnectTransportForRecovery() => disconnectTransportForHubConnectionRecovery(
    transportClient: input.transportClient,
    logResiliencePrefix: logResiliencePrefix,
    reconfigureTransportCallbacks: scratch.connectionSessionOrchestrator.configureTransportCallbacks,
  );

  Future<TokenRefreshResult> tryRefreshToken(HubConnectionContext context) => tryRefreshHubConnectionToken(
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

  assembleHubConnectionRecoveryCoordinators(
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

  assembleHubConnectionSessionCoordinators(
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

  return HubConnectionCoordinatorBundle(
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
