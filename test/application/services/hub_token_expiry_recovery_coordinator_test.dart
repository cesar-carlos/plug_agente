import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_runner.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/services/hub_token_expiry_recovery_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

HubProactiveTokenRefreshRunner _proactiveRefreshRunner() {
  return HubProactiveTokenRefreshRunner(
    runtime: HubProactiveTokenRefreshRuntimeDependencies(
      tokenRefreshGate: HubAccessTokenRefreshGate(minInterval: Duration.zero),
      isDisconnectRequested: () => false,
      isConnected: () => true,
      isSessionAuthInvalid: () => false,
      resolveConnectionContext: () => null,
      resolveAuthTokenForReconnect: () => null,
      tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
      disconnectTransport: () async {},
      attemptReconnect: (_, _, {authToken, recordErrorMessage = true}) async => false,
      kickHubTransportRecovery: ({required String trigger}) {},
      onTerminalRefreshFailure: () {},
      rescheduleProactiveRefresh: () {},
    ),
  );
}

HubTokenExpiryRecoveryRuntimeDependencies _runtimeDeps({
  required _MockHubResilienceCoordinator resilienceCoordinator,
  bool disconnectRequested = false,
  bool internalReconnecting = false,
  HubConnectionContext? context,
  Future<TokenRefreshResult> Function(HubConnectionContext context)? tryRefreshToken,
  void Function()? onMissingContext,
  void Function()? onRefreshFailed,
}) {
  return HubTokenExpiryRecoveryRuntimeDependencies(
    resilienceCoordinator: resilienceCoordinator,
    resilienceLogPrefix: () => 'test:',
    isDisconnectRequested: () => disconnectRequested,
    isInternalReconnecting: () => internalReconnecting,
    resolveConnectionContext: () => context,
    tryRefreshToken: tryRefreshToken ?? (_) async => const TokenRefreshResult.skippedByCooldown(),
    disconnectTransport: () async {},
    reconfigureTransportCallbacks: () {},
    attemptReconnect: (_, _, {authToken, recordErrorMessage = true}) async => false,
    recoverConnection: (_) async => false,
    startPersistentRetry: () {},
    beginTokenExpiryRecovery: () {},
    endTokenExpiryRecovery: () {},
    onMissingConnectionContextForTokenRefresh: onMissingContext ?? () {},
    onTokenRefreshFailed: onRefreshFailed ?? () {},
    onTokenRefreshException: (_) {},
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

  test('returns immediately when disconnect was requested', () async {
    var refreshCalled = false;
    final coordinator = HubTokenExpiryRecoveryCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        disconnectRequested: true,
        tryRefreshToken: (_) async {
          refreshCalled = true;
          return const TokenRefreshResult.refreshed('token');
        },
      ),
      proactiveRefreshRunner: _proactiveRefreshRunner(),
    );

    await coordinator.handleTokenExpired();

    expect(refreshCalled, isFalse);
    verifyNever(() => resilienceCoordinator.beginResilienceRecovery());
  });

  test('refreshes token only during internal reconnect burst', () async {
    var refreshCount = 0;
    const context = HubConnectionContext(
      configId: 'cfg-1',
      serverUrl: 'http://hub',
      agentId: 'agent-1',
    );

    final coordinator = HubTokenExpiryRecoveryCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        internalReconnecting: true,
        context: context,
        tryRefreshToken: (_) async {
          refreshCount++;
          return const TokenRefreshResult.refreshed('token');
        },
      ),
      proactiveRefreshRunner: _proactiveRefreshRunner(),
    );

    await coordinator.handleTokenExpired();

    expect(refreshCount, 1);
    verifyNever(() => resilienceCoordinator.beginResilienceRecovery());
  });

  test('reports missing context when token expiry recovery cannot resolve session', () async {
    var missingContextReported = false;

    final coordinator = HubTokenExpiryRecoveryCoordinator(
      runtime: _runtimeDeps(
        resilienceCoordinator: resilienceCoordinator,
        onMissingContext: () => missingContextReported = true,
      ),
      proactiveRefreshRunner: _proactiveRefreshRunner(),
    );

    await coordinator.handleTokenExpired();

    expect(missingContextReported, isTrue);
    verify(() => resilienceCoordinator.clearResilienceRecovery()).called(1);
  });
}
