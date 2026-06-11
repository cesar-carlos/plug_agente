import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_reconnect_attempt_coordinator.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectToHub extends Mock implements ConnectToHub {}

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

void main() {
  late _MockConnectToHub connectToHub;
  late _MockHubResilienceCoordinator resilienceCoordinator;
  late HubReconnectAttemptCoordinator coordinator;
  late bool disconnectRequested;
  late bool reconnectingUiState;
  late int quietFailureCount;
  late String? reconnectFailureMessage;
  late HubRecoveryUiHint? uiHint;
  late int connectSuccessNotes;
  late int connectFailureNotes;

  setUp(() {
    connectToHub = _MockConnectToHub();
    resilienceCoordinator = _MockHubResilienceCoordinator();
    disconnectRequested = false;
    reconnectingUiState = true;
    quietFailureCount = 0;
    reconnectFailureMessage = null;
    uiHint = null;
    connectSuccessNotes = 0;
    connectFailureNotes = 0;

    coordinator = HubReconnectAttemptCoordinator(
      runtime: HubReconnectAttemptRuntimeDependencies(
        connectToHubUseCase: connectToHub,
        resilienceCoordinator: resilienceCoordinator,
        onTransportConnectSuccessDuringRecovery: () => connectSuccessNotes++,
        onTransportConnectFailureDuringRecovery: () => connectFailureNotes++,
        resilienceLogPrefix: () => '',
        isDisconnectRequested: () => disconnectRequested,
        isReconnectingUiState: () => reconnectingUiState,
        cancelPersistentRetryTimer: () {},
        onTransportReconnectSuccess: ({required serverUrl, required agentId, authToken}) {},
        onTransportReconnectFailure: ({required message}) => reconnectFailureMessage = message,
        resetReconnectQuietFailureLogCount: () => quietFailureCount = 0,
        bumpReconnectQuietFailureLogCount: () => ++quietFailureCount,
        setHubRecoveryUiHint: (hint) => uiHint = hint,
        clearHubRecoveryUiHint: () => uiHint = HubRecoveryUiHint.none,
      ),
    );
  });

  test('returns false immediately when disconnect was requested', () async {
    disconnectRequested = true;
    when(
      () => resilienceCoordinator.runSerializedHubConnect<bool>(any(), staleResult: false),
    ).thenAnswer((invocation) async {
      final operation = invocation.positionalArguments[0] as Future<bool> Function();
      return operation();
    });

    final connected = await coordinator.attemptReconnect('http://hub', 'agent-1');

    expect(connected, isFalse);
    verifyNever(() => connectToHub(any(), any(), authToken: any(named: 'authToken')));
  });

  test('returns true and clears ui hint when transport connect succeeds', () async {
    when(() => connectToHub('http://hub', 'agent-1', authToken: 'token')).thenAnswer((_) async => const Success(unit));
    when(
      () => resilienceCoordinator.runSerializedHubConnect<bool>(any(), staleResult: false),
    ).thenAnswer((invocation) async {
      final operation = invocation.positionalArguments[0] as Future<bool> Function();
      return operation();
    });

    final connected = await coordinator.attemptReconnect(
      'http://hub',
      'agent-1',
      authToken: 'token',
    );

    expect(connected, isTrue);
    expect(uiHint, HubRecoveryUiHint.none);
    expect(connectSuccessNotes, 1);
  });

  test('records reconnect failure and returns false when transport connect fails', () async {
    final failure = domain_failures.NetworkFailure('offline');
    when(
      () => connectToHub('http://hub', 'agent-1', authToken: any(named: 'authToken')),
    ).thenAnswer((_) async => Failure(failure));
    when(
      () => resilienceCoordinator.runSerializedHubConnect<bool>(any(), staleResult: false),
    ).thenAnswer((invocation) async {
      final operation = invocation.positionalArguments[0] as Future<bool> Function();
      return operation();
    });

    final connected = await coordinator.attemptReconnect('http://hub', 'agent-1');

    expect(connected, isFalse);
    expect(reconnectFailureMessage, failure.message);
    expect(connectFailureNotes, 1);
  });
}
