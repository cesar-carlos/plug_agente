import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_hard_relogin_executor.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const HubConnectionContext(
        configId: 'cfg-fallback',
        serverUrl: 'http://hub',
        agentId: 'agent-fallback',
      ),
    );
    registerFallbackValue(const Duration(seconds: 30));
  });

  late _MockHubResilienceCoordinator resilienceCoordinator;
  late HubHardReloginExecutor executor;
  late HubRecoveryUiHint? uiHint;
  late String? hardReloginError;
  late String? storedToken;

  const context = HubConnectionContext(
    configId: 'cfg-1',
    serverUrl: 'http://hub',
    agentId: 'agent-1',
  );

  setUp(() {
    resilienceCoordinator = _MockHubResilienceCoordinator();
    uiHint = null;
    hardReloginError = null;
    storedToken = null;

    executor = HubHardReloginExecutor(
      runtime: HubHardReloginRuntimeDependencies(
        resilienceCoordinator: resilienceCoordinator,
        hardReloginCooldown: const Duration(seconds: 30),
        setHubRecoveryUiHint: (hint) => uiHint = hint,
        clearHubRecoveryUiHint: () => uiHint = HubRecoveryUiHint.none,
        cancelPersistentRetryTimer: () {},
        onAuthBridgeUnavailable: () => hardReloginError = 'auth-bridge-unavailable',
        onHardReloginFailed: (message) => hardReloginError = message,
        onHardReloginSuccess: (token) {
          storedToken = token;
          return token;
        },
      ),
    );
  });

  test('returns null and clears hint when hard relogin is skipped by cooldown', () async {
    when(
      () => resilienceCoordinator.executeHardRelogin(
        context,
        logSummary: any(named: 'logSummary'),
        hardReloginCooldown: any(named: 'hardReloginCooldown'),
        ignoreCooldown: any(named: 'ignoreCooldown'),
      ),
    ).thenAnswer((_) async => const HardReloginResult(outcome: HardReloginOutcome.skippedCooldown));

    final token = await executor.execute(context, logSummary: 'burst');

    expect(token, isNull);
    expect(uiHint, HubRecoveryUiHint.none);
  });

  test('stores token when hard relogin succeeds', () async {
    when(
      () => resilienceCoordinator.executeHardRelogin(
        context,
        logSummary: any(named: 'logSummary'),
        hardReloginCooldown: any(named: 'hardReloginCooldown'),
        ignoreCooldown: any(named: 'ignoreCooldown'),
      ),
    ).thenAnswer((_) async => const HardReloginResult(outcome: HardReloginOutcome.success, token: 'fresh-token'));

    final token = await executor.execute(context, logSummary: 'burst');

    expect(token, 'fresh-token');
    expect(storedToken, 'fresh-token');
  });

  test('surfaces failure message when hard relogin fails', () async {
    when(
      () => resilienceCoordinator.executeHardRelogin(
        context,
        logSummary: any(named: 'logSummary'),
        hardReloginCooldown: any(named: 'hardReloginCooldown'),
        ignoreCooldown: any(named: 'ignoreCooldown'),
      ),
    ).thenAnswer(
      (_) async => const HardReloginResult(
        outcome: HardReloginOutcome.failed,
        failureMessage: 'sign-in failed',
      ),
    );
    when(() => resilienceCoordinator.clearResilienceRecovery()).thenReturn(null);

    final token = await executor.execute(context, logSummary: 'burst');

    expect(token, isNull);
    expect(hardReloginError, 'sign-in failed');
    verify(() => resilienceCoordinator.clearResilienceRecovery()).called(1);
  });
}
