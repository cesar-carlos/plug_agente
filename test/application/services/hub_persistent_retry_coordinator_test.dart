import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/services/hub_persistent_retry_coordinator.dart';
import 'package:plug_agente/application/services/hub_recovery_orchestrator.dart';
import 'package:plug_agente/application/services/hub_recovery_runtime_dependencies.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/constants/transport_reconnect_constants.dart';
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

const _context = HubConnectionContext(
  configId: 'cfg',
  serverUrl: 'http://hub',
  agentId: 'agent-1',
);

void main() {
  test('start runs tick immediately and resets counters', () async {
    var tickCount = 0;
    var resetCount = 0;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: () => 3,
        maxUnreachableFailedTicks: () => 160,
        persistentRetryInterval: () => const Duration(milliseconds: 30),
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {
          tickCount++;
        },
        resetPersistentRetryCounters: () => resetCount++,
        onPersistentRetryExhausted: (_, _) {},
      ),
    );

    coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 45));
    coordinator.cancelTimer();

    expect(tickCount, greaterThanOrEqualTo(1));
    expect(resetCount, 1);
    expect(coordinator.hasActiveTimer, isFalse);
  });

  test('bumpPersistentReconnectFailure reports exhaustion at socket threshold', () {
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
        maxFailedTicks: () => 2,
        maxUnreachableFailedTicks: () => 160,
        persistentRetryInterval: () => const Duration(seconds: 45),
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {},
        resetPersistentRetryCounters: orchestrator.resetPersistentRetryCounters,
        onPersistentRetryExhausted: (context, count) {
          exhaustedContext = context;
          exhaustedFailures = count;
        },
      ),
    );

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );
    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );

    expect(exhaustedContext?.agentId, 'agent-1');
    expect(exhaustedFailures, 2);
    expect(orchestrator.persistentFailureCount, 2);
    expect(orchestrator.persistentUnreachableFailureCount, 0);
  });

  test('increments persistentFailureCount without exhausting when maxFailedTicks is 0', () {
    final orchestrator = HubRecoveryOrchestrator(
      initialReconnectDelay: const Duration(seconds: 1),
      maxReconnectDelay: const Duration(seconds: 2),
      runtime: _minimalRecoveryRuntime(),
    );
    var exhausted = false;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: () => 0,
        maxUnreachableFailedTicks: () => 160,
        persistentRetryInterval: () => const Duration(seconds: 45),
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {},
        resetPersistentRetryCounters: orchestrator.resetPersistentRetryCounters,
        onPersistentRetryExhausted: (_, _) {
          exhausted = true;
        },
      ),
    );

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );
    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );

    expect(orchestrator.persistentFailureCount, 2);
    expect(exhausted, isFalse);
    expect(coordinator.hasActiveTimer, isFalse);
  });

  test('unreachable failures exhaust only the unreachable budget', () {
    final orchestrator = HubRecoveryOrchestrator(
      initialReconnectDelay: const Duration(seconds: 1),
      maxReconnectDelay: const Duration(seconds: 2),
      runtime: _minimalRecoveryRuntime(),
    );
    var exhausted = false;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: () => 1,
        maxUnreachableFailedTicks: () => 2,
        persistentRetryInterval: () => const Duration(seconds: 45),
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {},
        resetPersistentRetryCounters: orchestrator.resetPersistentRetryCounters,
        onPersistentRetryExhausted: (_, _) {
          exhausted = true;
        },
      ),
    );

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.hubUnreachableReason,
      orchestrator: orchestrator,
    );
    expect(exhausted, isFalse);
    expect(orchestrator.persistentUnreachableFailureCount, 1);
    expect(orchestrator.persistentFailureCount, 0);

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.hubUnreachableReason,
      orchestrator: orchestrator,
    );
    expect(exhausted, isTrue);
    expect(orchestrator.persistentUnreachableFailureCount, 2);
    expect(orchestrator.persistentFailureCount, 0);
  });

  test('socket failures do not consume unreachable budget', () {
    final orchestrator = HubRecoveryOrchestrator(
      initialReconnectDelay: const Duration(seconds: 1),
      maxReconnectDelay: const Duration(seconds: 2),
      runtime: _minimalRecoveryRuntime(),
    );
    var exhausted = false;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: () => 0,
        maxUnreachableFailedTicks: () => 1,
        persistentRetryInterval: () => const Duration(seconds: 45),
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {},
        resetPersistentRetryCounters: orchestrator.resetPersistentRetryCounters,
        onPersistentRetryExhausted: (_, _) {
          exhausted = true;
        },
      ),
    );

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );
    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );

    expect(exhausted, isFalse);
    expect(orchestrator.persistentFailureCount, 2);
    expect(orchestrator.persistentUnreachableFailureCount, 0);
  });

  test('start re-reads effective interval and budgets from getters', () async {
    var interval = const Duration(milliseconds: 80);
    var maxFailed = 9;
    var startedWithIntervalMs = 0;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: () => maxFailed,
        maxUnreachableFailedTicks: () => 160,
        persistentRetryInterval: () => interval,
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {},
        resetPersistentRetryCounters: () {},
        onPersistentRetryExhausted: (_, _) {},
      ),
    );

    interval = const Duration(milliseconds: 40);
    maxFailed = 3;
    coordinator.start();
    startedWithIntervalMs = interval.inMilliseconds;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    coordinator.cancelTimer();

    expect(startedWithIntervalMs, 40);
    expect(maxFailed, 3);
  });

  test('session budgets ignore mid-flight getter changes until next start', () {
    final orchestrator = HubRecoveryOrchestrator(
      initialReconnectDelay: const Duration(seconds: 1),
      maxReconnectDelay: const Duration(seconds: 2),
      runtime: _minimalRecoveryRuntime(),
    );
    var maxFailed = 2;
    var exhausted = false;
    final coordinator = HubPersistentRetryCoordinator(
      runtime: HubPersistentRetryRuntimeDependencies(
        resilienceLogPrefix: () => '',
        maxFailedTicks: () => maxFailed,
        maxUnreachableFailedTicks: () => 160,
        persistentRetryInterval: () => const Duration(days: 1),
        resolveConnectionContext: () => _context,
        runPersistentTick: () async {},
        resetPersistentRetryCounters: orchestrator.resetPersistentRetryCounters,
        onPersistentRetryExhausted: (_, _) {
          exhausted = true;
        },
      ),
    );

    coordinator.start();
    coordinator.cancelTimer();
    maxFailed = 1;

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );
    expect(exhausted, isFalse);

    coordinator.bumpPersistentReconnectFailure(
      _context,
      reason: TransportReconnectConstants.socketReconnectFailedReason,
      orchestrator: orchestrator,
    );
    expect(exhausted, isTrue);
    expect(orchestrator.persistentFailureCount, 2);
  });
}
