import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_manual_reconnection_coordinator.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

HubManualReconnectionRuntimeDependencies _runtimeDeps({
  required _MockHubResilienceCoordinator resilienceCoordinator,
  bool disconnectRequested = false,
  bool internalReconnecting = false,
  HubConnectionContext? context,
  Future<bool> Function(HubConnectionContext context)? recoverConnection,
  void Function()? onMissingContext,
  void Function()? onBurstExhausted,
  void Function()? onStartPersistentRetry,
}) {
  return HubManualReconnectionRuntimeDependencies(
    resilienceCoordinator: resilienceCoordinator,
    resilienceLogPrefix: () => 'test:',
    isDisconnectRequested: () => disconnectRequested,
    isInternalReconnecting: () => internalReconnecting,
    resolveConnectionContext: () => context,
    recoverConnection: recoverConnection ?? (_) async => false,
    startPersistentRetry: onStartPersistentRetry ?? () {},
    beginManualReconnection: () {},
    endManualReconnection: () {},
    onMissingConnectionContextForReconnection: onMissingContext ?? () {},
    onDisconnectDuringReconnection: () {},
    onBurstRecoveryExhausted: onBurstExhausted ?? () {},
    onReconnectionException: (_) {},
    clearHubRecoveryUiHint: () {},
    notifyStateChanged: () {},
  );
}

void main() {
  late _MockHubResilienceCoordinator resilienceCoordinator;

  setUp(() {
    resilienceCoordinator = _MockHubResilienceCoordinator();
    when(() => resilienceCoordinator.beginResilienceRecovery()).thenReturn(null);
    when(() => resilienceCoordinator.clearResilienceRecovery()).thenReturn(null);
  });

  test('skips handler when already reconnecting or disconnect requested', () async {
    var recoveryCalled = false;
    final coordinator = HubManualReconnectionCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        internalReconnecting: true,
        recoverConnection: (_) async {
          recoveryCalled = true;
          return true;
        },
      ),
    );

    await coordinator.handleReconnectionNeeded();

    expect(recoveryCalled, isFalse);
    verifyNever(() => resilienceCoordinator.beginResilienceRecovery());
  });

  test('reports missing context when reconnection cannot resolve session', () async {
    var missingContextReported = false;
    final coordinator = HubManualReconnectionCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        onMissingContext: () => missingContextReported = true,
      ),
    );

    await coordinator.handleReconnectionNeeded();

    expect(missingContextReported, isTrue);
    verifyNever(() => resilienceCoordinator.beginResilienceRecovery());
  });

  test('starts persistent retry when burst recovery is exhausted', () async {
    var persistentRetryStarted = false;
    var burstExhaustedReported = false;
    const context = HubConnectionContext(
      configId: 'cfg-1',
      serverUrl: 'http://hub',
      agentId: 'agent-1',
    );

    final coordinator = HubManualReconnectionCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        context: context,
        recoverConnection: (_) async => false,
        onBurstExhausted: () => burstExhaustedReported = true,
        onStartPersistentRetry: () => persistentRetryStarted = true,
      ),
    );

    await coordinator.handleReconnectionNeeded();

    expect(burstExhaustedReported, isTrue);
    expect(persistentRetryStarted, isTrue);
    verify(() => resilienceCoordinator.beginResilienceRecovery()).called(1);
  });

  test('completes without persistent retry when burst recovery succeeds', () async {
    var persistentRetryStarted = false;
    const context = HubConnectionContext(
      configId: 'cfg-1',
      serverUrl: 'http://hub',
      agentId: 'agent-1',
    );

    final coordinator = HubManualReconnectionCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        context: context,
        recoverConnection: (_) async => true,
        onStartPersistentRetry: () => persistentRetryStarted = true,
      ),
    );

    await coordinator.handleReconnectionNeeded();

    expect(persistentRetryStarted, isFalse);
    verify(() => resilienceCoordinator.beginResilienceRecovery()).called(1);
  });
}
