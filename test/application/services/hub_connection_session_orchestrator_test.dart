import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/services/hub_connection_session_orchestrator.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectToHub extends Mock implements ConnectToHub {}

class _MockTransportClient extends Mock implements ITransportClient {}

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

class _FakeConnectionContextSource implements IConnectionContextSource {
  HubConnectionContext? context;

  @override
  HubConnectionContext? resolveConnectionContext() => context;

  @override
  String? resolveAuthTokenForReconnect() => null;

  @override
  String resolveActiveConfigId(String? candidateConfigId) => candidateConfigId ?? 'cfg-1';
}

class _FakeHubRecoveryUiSink implements HubRecoveryUiSink {
  @override
  void clearHubRecoveryUiHint() {}

  @override
  void setHubRecoveryUiHint(_) {}
}

HubRecoveryOrchestrator _hubRecoveryOrchestrator(_MockHubResilienceCoordinator resilience) {
  return HubRecoveryOrchestrator(
    initialReconnectDelay: const Duration(seconds: 1),
    maxReconnectDelay: const Duration(seconds: 2),
    runtime: HubRecoveryRuntimeDependencies(
      resilienceCoordinator: resilience,
      contextSource: _FakeConnectionContextSource(),
      checkHubAvailability: null,
      uiSink: _FakeHubRecoveryUiSink(),
      resilienceLogPrefix: () => '',
      isDisconnectRequested: () => false,
      tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
      attemptReconnect: (_, _, {authToken, recordErrorMessage = true}) async => false,
      disconnectTransportForRecovery: () async {},
      executeHardRelogin: (_, {required logSummary, ignoreCooldown = false}) async => null,
      bumpPersistentReconnectFailure: (_, {required reason}) {},
      isStatusError: () => false,
      cancelPersistentRetryTimer: () {},
    ),
  );
}

HubConnectionSessionRuntimeDependencies _runtimeDeps({
  required _MockConnectToHub connectToHub,
  required _MockTransportClient transportClient,
  required _MockHubResilienceCoordinator resilienceCoordinator,
  required HubRecoveryOrchestrator hubRecoveryOrchestrator,
  required _FakeConnectionContextSource contextSource,
  bool disconnectRequested = false,
  bool recoveryInProgress = false,
  void Function()? onEnterNegotiating,
  void Function()? onStartPersistentRetry,
  void Function(String message)? onConnectFailure,
}) {
  return HubConnectionSessionRuntimeDependencies(
    connectToHubUseCase: connectToHub,
    transportClient: transportClient,
    resilienceCoordinator: resilienceCoordinator,
    hubRecoveryOrchestrator: hubRecoveryOrchestrator,
    contextSource: contextSource,
    resilienceLogPrefix: () => 'test:',
    isDisconnectRequested: () => disconnectRequested,
    setDisconnectRequested: (_) {},
    clearHubRecoveryUiHint: () {},
    notifyStateChanged: () {},
    cancelPersistentRetryTimer: () {},
    startPersistentRetry: onStartPersistentRetry ?? () {},
    enterNegotiatingState: onEnterNegotiating ?? () {},
    resetReconnectQuietFailureLogCount: () {},
    cancelProactiveTokenRefreshSchedule: () {},
    clearHubAccessTokenRenewerAuthBridge: () {},
    handleTokenExpired: () async {},
    scheduleExclusiveRecovery: () async {},
    handleHubLifecycle: (_) {},
    prepareConnectSession: ({required serverUrl, required agentId, required configId, authToken}) {},
    preparePersistentRecoverySession: ({required configId, required serverUrl, required agentId, authToken}) {},
    resetSessionAuthInvalid: () {},
    clearTrackedAuthToken: () {},
    beginConnecting: () {},
    enterDisconnected: ({bool clearError = false}) {},
    enterReconnecting: ({required bool clearError}) {},
    onConnectFailure: onConnectFailure ?? (_) {},
    isRecoveryAlreadyInProgress: () => recoveryInProgress,
  );
}

void main() {
  late _MockConnectToHub connectToHub;
  late _MockTransportClient transportClient;
  late _MockHubResilienceCoordinator resilienceCoordinator;
  late HubRecoveryOrchestrator hubRecoveryOrchestrator;
  late _FakeConnectionContextSource contextSource;

  setUp(() {
    connectToHub = _MockConnectToHub();
    transportClient = _MockTransportClient();
    resilienceCoordinator = _MockHubResilienceCoordinator();
    hubRecoveryOrchestrator = _hubRecoveryOrchestrator(resilienceCoordinator);
    contextSource = _FakeConnectionContextSource();

    when(() => resilienceCoordinator.resetAuthRecoveryState()).thenReturn(null);
    when(() => resilienceCoordinator.invalidateHubConnectEpoch()).thenReturn(null);
    when(() => resilienceCoordinator.clearResilienceRecovery()).thenReturn(null);
    when(() => resilienceCoordinator.cancelNegotiatingWatchdog()).thenReturn(null);
    when(
      () => resilienceCoordinator.runSerializedHubConnect<Result<void>>(any()),
    ).thenAnswer((invocation) async {
      final operation = invocation.positionalArguments[0] as Future<Result<void>> Function();
      return operation();
    });
    when(() => transportClient.setOnTokenExpired(any())).thenReturn(null);
    when(() => transportClient.setOnReconnectionNeeded(any())).thenReturn(null);
    when(() => transportClient.setOnHubLifecycle(any())).thenReturn(null);
    when(() => transportClient.disconnect()).thenAnswer((_) async => const Success(unit));
  });

  test('connect enters negotiating state when transport connect succeeds', () async {
    var enteredNegotiating = false;
    when(() => connectToHub('http://hub', 'agent-1', authToken: any(named: 'authToken')))
        .thenAnswer((_) async => const Success(unit));

    final orchestrator = HubConnectionSessionOrchestrator(
      runtime: _runtimeDeps(
        connectToHub: connectToHub,
        transportClient: transportClient,
        resilienceCoordinator: resilienceCoordinator,
        hubRecoveryOrchestrator: hubRecoveryOrchestrator,
        contextSource: contextSource,
        onEnterNegotiating: () => enteredNegotiating = true,
      ),
    );

    final result = await orchestrator.connect('http://hub', 'agent-1');

    expect(result.isSuccess(), isTrue);
    expect(enteredNegotiating, isTrue);
    expect(hubRecoveryOrchestrator.persistentFailureCount, 0);
    verify(() => transportClient.setOnTokenExpired(any())).called(1);
  });

  test('connect starts persistent retry when recoverOnFailure and context exists', () async {
    var persistentRetryStarted = false;
    final failure = domain_failures.NetworkFailure('offline');
    contextSource.context = const HubConnectionContext(
      configId: 'cfg-1',
      serverUrl: 'http://hub',
      agentId: 'agent-1',
    );
    when(() => connectToHub('http://hub', 'agent-1', authToken: any(named: 'authToken')))
        .thenAnswer((_) async => Failure(failure));
    when(() => resilienceCoordinator.beginResilienceRecovery()).thenReturn(null);

    final orchestrator = HubConnectionSessionOrchestrator(
      runtime: _runtimeDeps(
        connectToHub: connectToHub,
        transportClient: transportClient,
        resilienceCoordinator: resilienceCoordinator,
        hubRecoveryOrchestrator: hubRecoveryOrchestrator,
        contextSource: contextSource,
        onStartPersistentRetry: () => persistentRetryStarted = true,
      ),
    );

    final result = await orchestrator.connect(
      'http://hub',
      'agent-1',
      recoverOnFailure: true,
    );

    expect(result.isError(), isTrue);
    expect(persistentRetryStarted, isTrue);
    verify(() => resilienceCoordinator.beginResilienceRecovery()).called(1);
  });

  test('disconnect clears recovery state and disconnects transport', () async {
    hubRecoveryOrchestrator.consecutiveReconnectFailures = 2;

    final orchestrator = HubConnectionSessionOrchestrator(
      runtime: _runtimeDeps(
        connectToHub: connectToHub,
        transportClient: transportClient,
        resilienceCoordinator: resilienceCoordinator,
        hubRecoveryOrchestrator: hubRecoveryOrchestrator,
        contextSource: contextSource,
      ),
    );

    await orchestrator.disconnect();

    expect(hubRecoveryOrchestrator.consecutiveReconnectFailures, 0);
    verify(() => transportClient.disconnect()).called(1);
    verify(() => resilienceCoordinator.clearResilienceRecovery()).called(1);
  });
}
