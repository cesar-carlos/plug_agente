import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/coordinators/hub_connection/hub_connection_coordinator_assembly.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/state/hub_connection_display_state.dart';
import 'package:plug_agente/application/state/hub_connection_tracking_state.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectToHub extends Mock implements ConnectToHub {}

class _MockTransportClient extends Mock implements ITransportClient {}

class _MockCheckHubAvailability extends Mock implements CheckHubAvailability {}

class _MockConnectionContextSource extends Mock implements IConnectionContextSource {}

class _RecordingUiSink implements HubRecoveryUiSink {
  HubRecoveryUiHint hint = HubRecoveryUiHint.none;

  @override
  void clearHubRecoveryUiHint() {
    hint = HubRecoveryUiHint.none;
  }

  @override
  void setHubRecoveryUiHint(HubRecoveryUiHint value) {
    hint = value;
  }
}

HubConnectionCoordinatorAssemblyInput _assemblyInput({
  required ConnectToHub connectToHub,
  required ITransportClient transportClient,
  required IConnectionContextSource contextSource,
  required HubConnectionDisplayState displayState,
  required HubConnectionTrackingState trackingState,
  required HubRecoveryUiSink uiSink,
}) {
  return HubConnectionCoordinatorAssemblyInput(
    connectToHubUseCase: connectToHub,
    transportClient: transportClient,
    checkHubAvailabilityUseCase: _MockCheckHubAvailability(),
    contextSource: contextSource,
    hubRecoveryAuthBridge: null,
    hubAccessTokenRefreshGate: HubAccessTokenRefreshGate(),
    hubAccessTokenRenewer: null,
    displayState: displayState,
    connectionTrackingState: trackingState,
    uiSink: uiSink,
    isDisconnectRequested: () => false,
    setDisconnectRequested: (_) {},
    reconnectQuietFailureLogCount: () => 0,
    setReconnectQuietFailureLogCount: (_) {},
    resetReconnectQuietFailureLogCount: () {},
    bumpReconnectQuietFailureLogCount: () => 0,
    notifyStateChanged: () {},
    onNegotiatingWatchdogTimeoutWithoutContext: ({required int timeoutMs}) {},
    onNegotiatingWatchdogTimeoutWithContext: () {},
    resolveProactiveRefreshAccessToken: () => null,
    resolveAuthProviderError: () => null,
    normalizeToken: (token) => token?.trim(),
    initialReconnectDelay: const Duration(milliseconds: 100),
    maxReconnectDelay: const Duration(seconds: 1),
    tokenRefreshIntervalAttempts: 3,
    maxReconnectAttempts: 5,
    effectiveHardReloginRecoveryEnabled: false,
    effectiveHardReloginFailureThreshold: 3,
    effectiveHubPersistentRetryMaxFailedTicks: () => 10,
    effectiveHubPersistentUnreachableMaxFailedTicks: () => 160,
    effectiveHubPersistentRetryInterval: () => const Duration(seconds: 30),
    effectiveHubHardReloginCooldown: const Duration(minutes: 5),
    hasAuthBridge: false,
  );
}

void main() {
  late _MockConnectToHub connectToHub;
  late _MockTransportClient transportClient;
  late HubConnectionDisplayState displayState;
  late HubConnectionTrackingState trackingState;
  late _MockConnectionContextSource contextSource;
  late _RecordingUiSink uiSink;

  setUp(() {
    connectToHub = _MockConnectToHub();
    transportClient = _MockTransportClient();
    displayState = HubConnectionDisplayState();
    trackingState = HubConnectionTrackingState();
    contextSource = _MockConnectionContextSource();
    uiSink = _RecordingUiSink();

    when(() => transportClient.disconnect()).thenAnswer((_) async => const Success(unit));
    when(() => transportClient.setResilienceLogContext(any())).thenReturn(null);
    when(() => contextSource.resolveConnectionContext()).thenReturn(
      const HubConnectionContext(
        configId: 'cfg-1',
        serverUrl: 'https://hub.test',
        agentId: 'agent-1',
      ),
    );
  });

  group('assembleHubConnectionCoordinators', () {
    test('wires circular late dependencies without throwing', () {
      expect(
        () => assembleHubConnectionCoordinators(
          _assemblyInput(
            connectToHub: connectToHub,
            transportClient: transportClient,
            contextSource: contextSource,
            displayState: displayState,
            trackingState: trackingState,
            uiSink: uiSink,
          ),
        ),
        returnsNormally,
      );
    });

    test('returns bundle with all coordinators initialized', () {
      final bundle = assembleHubConnectionCoordinators(
        _assemblyInput(
          connectToHub: connectToHub,
          transportClient: transportClient,
          contextSource: contextSource,
          displayState: displayState,
          trackingState: trackingState,
          uiSink: uiSink,
        ),
      );

      expect(bundle.resilienceCoordinator, isNotNull);
      expect(bundle.hubRecoveryOrchestrator, isNotNull);
      expect(bundle.proactiveTokenRefreshRunner, isNotNull);
      expect(bundle.tokenExpiryRecoveryCoordinator, isNotNull);
      expect(bundle.manualReconnectionCoordinator, isNotNull);
      expect(bundle.persistentRetryCoordinator, isNotNull);
      expect(bundle.proactiveTokenRefreshScheduler, isNotNull);
      expect(bundle.hubTransportLifecycleCoordinator, isNotNull);
      expect(bundle.reconnectAttemptCoordinator, isNotNull);
      expect(bundle.hardReloginExecutor, isNotNull);
      expect(bundle.connectionSessionOrchestrator, isNotNull);
    });

    test('connectionSessionOrchestrator can configure transport callbacks after assembly', () {
      final bundle = assembleHubConnectionCoordinators(
        _assemblyInput(
          connectToHub: connectToHub,
          transportClient: transportClient,
          contextSource: contextSource,
          displayState: displayState,
          trackingState: trackingState,
          uiSink: uiSink,
        ),
      );

      expect(bundle.connectionSessionOrchestrator.configureTransportCallbacks, returnsNormally);
    });

    test('resilience coordinator can resolve log prefix after full wiring', () {
      trackingState.lastConfigId = 'cfg-1';
      trackingState.lastServerUrl = 'https://hub.test';
      trackingState.lastAgentId = 'agent-1';

      final bundle = assembleHubConnectionCoordinators(
        _assemblyInput(
          connectToHub: connectToHub,
          transportClient: transportClient,
          contextSource: contextSource,
          displayState: displayState,
          trackingState: trackingState,
          uiSink: uiSink,
        ),
      );

      expect(bundle.resilienceCoordinator.resilienceLogPrefix, returnsNormally);
      expect(contextSource.resolveConnectionContext(), isA<HubConnectionContext>());
    });
  });
}
