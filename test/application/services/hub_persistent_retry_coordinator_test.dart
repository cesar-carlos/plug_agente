import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/services/hub_persistent_retry_coordinator.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

class _FakeConnectionContextSource implements IConnectionContextSource {
  @override
  HubConnectionContext? resolveConnectionContext() => null;

  @override
  String? resolveAuthTokenForReconnect() => null;

  @override
  String resolveActiveConfigId(String? candidateConfigId) => candidateConfigId ?? 'cfg';
}

class _FakeHubRecoveryUiSink implements HubRecoveryUiSink {
  @override
  void clearHubRecoveryUiHint() {}

  @override
  void setHubRecoveryUiHint(HubRecoveryUiHint hint) {}
}

HubRecoveryRuntimeDependencies _minimalRecoveryRuntime() {
  return HubRecoveryRuntimeDependencies(
    resilienceCoordinator: _MockHubResilienceCoordinator(),
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
  );
}

void main() {
  test('start runs tick immediately and resets counters', () async {
    var tickCount = 0;
    var resetCount = 0;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: 3,
        resolveConnectionContext: () => const HubConnectionContext(
          configId: 'cfg',
          serverUrl: 'http://hub',
          agentId: 'agent-1',
        ),
        runPersistentTick: () async {
          tickCount++;
        },
        resetPersistentRetryCounters: () => resetCount++,
        onPersistentRetryExhausted: (_, _) {},
      ),
    );

    coordinator.start(interval: const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 45));
    coordinator.cancelTimer();

    expect(tickCount, greaterThanOrEqualTo(1));
    expect(resetCount, 1);
    expect(coordinator.hasActiveTimer, isFalse);
  });

  test('bumpPersistentReconnectFailure reports exhaustion at threshold', () {
    final orchestrator = HubRecoveryOrchestrator(
      initialReconnectDelay: const Duration(seconds: 1),
      maxReconnectDelay: const Duration(seconds: 2),
      runtime: _minimalRecoveryRuntime(),
    );
    HubConnectionContext? exhaustedContext;
    var exhaustedFailures = 0;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: 2,
        resolveConnectionContext: () => const HubConnectionContext(
          configId: 'cfg',
          serverUrl: 'http://hub',
          agentId: 'agent-1',
        ),
        runPersistentTick: () async {},
        resetPersistentRetryCounters: orchestrator.resetPersistentRetryCounters,
        onPersistentRetryExhausted: (context, count) {
          exhaustedContext = context;
          exhaustedFailures = count;
        },
      ),
    );

    const context = HubConnectionContext(
      configId: 'cfg',
      serverUrl: 'http://hub',
      agentId: 'agent-1',
    );

    coordinator.bumpPersistentReconnectFailure(context, reason: 'one', orchestrator: orchestrator);
    coordinator.bumpPersistentReconnectFailure(context, reason: 'two', orchestrator: orchestrator);

    expect(exhaustedContext?.agentId, 'agent-1');
    expect(exhaustedFailures, 2);
    expect(orchestrator.persistentFailureCount, 2);
  });
}
