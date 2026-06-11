import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/hub_access_token_refresh_gate.dart';
import 'package:plug_agente/application/services/hub_proactive_token_refresh_runner.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';

void main() {
  test('run skips when disconnected', () async {
    var refreshCalls = 0;
    final runner = HubProactiveTokenRefreshRunner(
      runtime: HubProactiveTokenRefreshRuntimeDependencies(
        tokenRefreshGate: HubAccessTokenRefreshGate(),
        isDisconnectRequested: () => true,
        isConnected: () => true,
        isSessionAuthInvalid: () => false,
        resolveConnectionContext: () => const HubConnectionContext(
          configId: 'cfg',
          serverUrl: 'http://hub',
          agentId: 'agent-1',
        ),
        resolveAuthTokenForReconnect: () => 'tok',
        tryRefreshToken: (_) async {
          refreshCalls++;
          return const TokenRefreshResult.skippedByCooldown();
        },
        disconnectTransport: () async {},
        attemptReconnect: (_, _, {authToken, recordErrorMessage = true}) async => false,
        kickHubTransportRecovery: ({required String trigger}) {},
        onTerminalRefreshFailure: () {},
        rescheduleProactiveRefresh: () {},
      ),
    );

    await runner.run();

    expect(refreshCalls, 0);
  });

  test('resolveReconnectTokenAfterRefresh returns refreshed token', () async {
    final runner = HubProactiveTokenRefreshRunner(
      runtime: HubProactiveTokenRefreshRuntimeDependencies(
        tokenRefreshGate: HubAccessTokenRefreshGate(),
        isDisconnectRequested: () => false,
        isConnected: () => true,
        isSessionAuthInvalid: () => false,
        resolveConnectionContext: () => null,
        resolveAuthTokenForReconnect: () => 'fallback',
        tryRefreshToken: (_) async => const TokenRefreshResult.refreshed('new-token'),
        disconnectTransport: () async {},
        attemptReconnect: (_, _, {authToken, recordErrorMessage = true}) async => false,
        kickHubTransportRecovery: ({required String trigger}) {},
        onTerminalRefreshFailure: () {},
        rescheduleProactiveRefresh: () {},
      ),
    );

    final token = await runner.resolveReconnectTokenAfterRefresh(
      const HubConnectionContext(configId: 'cfg', serverUrl: 'http://hub', agentId: 'agent-1'),
      const TokenRefreshResult.refreshed('new-token'),
    );

    expect(token, 'new-token');
  });
}
