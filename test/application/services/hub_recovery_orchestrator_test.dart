import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
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

class _FakeHubContextSource implements IConnectionContextSource {
  @override
  HubConnectionContext? resolveConnectionContext() => const HubConnectionContext(
    configId: 'cfg-1',
    serverUrl: 'https://hub.test',
    agentId: 'agent-1',
  );

  @override
  String? resolveAuthTokenForReconnect() => 'tok';

  @override
  String resolveActiveConfigId(String? candidateConfigId) => candidateConfigId ?? 'cfg-1';
}

class _FakeHubRecoveryUiSink implements HubRecoveryUiSink {
  @override
  void clearHubRecoveryUiHint() {}

  @override
  void setHubRecoveryUiHint(HubRecoveryUiHint hint) {}
}

HubRecoveryRuntimeDependencies _minimalRuntimeDeps() {
  return HubRecoveryRuntimeDependencies(
    resilienceCoordinator: _MockHubResilienceCoordinator(),
    contextSource: _FakeConnectionContextSource(),
    checkHubAvailability: null,
    uiSink: _FakeHubRecoveryUiSink(),
    resilienceLogPrefix: () => '',
    isDisconnectRequested: () => false,
    tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
    attemptReconnect: (String serverUrl, String agentId, {String? authToken, bool recordErrorMessage = true}) async =>
        false,
    disconnectTransportForRecovery: () async {},
    executeHardRelogin:
        (HubConnectionContext context, {required String logSummary, bool ignoreCooldown = false}) async => null,
    bumpPersistentReconnectFailure: (HubConnectionContext context, {required String reason}) {},
    isStatusError: () => false,
    cancelPersistentRetryTimer: () {},
  );
}

void main() {
  group('HubRecoveryOrchestrator', () {
    test('reconnectDelayForAttempt returns non-negative delay', () {
      final orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: const Duration(seconds: 1),
        maxReconnectDelay: const Duration(seconds: 60),
        runtime: _minimalRuntimeDeps(),
      );

      expect(orchestrator.reconnectDelayForAttempt(1).inMilliseconds, greaterThanOrEqualTo(0));
      expect(orchestrator.reconnectDelayForAttempt(3).inMilliseconds, greaterThanOrEqualTo(0));
    });

    test('shouldEscalateToHardRelogin is false until failure threshold', () {
      final orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: const Duration(seconds: 1),
        maxReconnectDelay: const Duration(seconds: 60),
        runtime: _minimalRuntimeDeps(),
      );

      expect(
        orchestrator.shouldEscalateToHardRelogin(recoveryEnabled: true, failureThreshold: 3),
        isFalse,
      );
      orchestrator.noteTransportConnectFailureDuringRecovery();
      orchestrator.noteTransportConnectFailureDuringRecovery();
      expect(
        orchestrator.shouldEscalateToHardRelogin(recoveryEnabled: true, failureThreshold: 3),
        isFalse,
      );
      orchestrator.noteTransportConnectFailureDuringRecovery();
      expect(
        orchestrator.shouldEscalateToHardRelogin(recoveryEnabled: true, failureThreshold: 3),
        isTrue,
      );
    });

    test('shouldEscalateToHardRelogin stays false when disabled or already attempted', () {
      final orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: const Duration(seconds: 1),
        maxReconnectDelay: const Duration(seconds: 60),
        runtime: _minimalRuntimeDeps(),
      );
      orchestrator.consecutiveReconnectFailures = 10;

      expect(
        orchestrator.shouldEscalateToHardRelogin(recoveryEnabled: false, failureThreshold: 1),
        isFalse,
      );
      expect(
        orchestrator.shouldEscalateToHardRelogin(recoveryEnabled: true, failureThreshold: 1),
        isTrue,
      );
      orchestrator.markHardReloginAttempted();
      expect(
        orchestrator.shouldEscalateToHardRelogin(recoveryEnabled: true, failureThreshold: 1),
        isFalse,
      );
    });

    test('resetForUserConnect clears burst counters', () {
      final orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: const Duration(seconds: 1),
        maxReconnectDelay: const Duration(seconds: 60),
        runtime: _minimalRuntimeDeps(),
      );
      orchestrator.consecutiveReconnectFailures = 5;
      orchestrator.hardReloginAttemptedInCycle = true;
      orchestrator.persistentFailureCount = 2;

      orchestrator.resetForUserConnect();

      expect(orchestrator.consecutiveReconnectFailures, 0);
      expect(orchestrator.hardReloginAttemptedInCycle, isFalse);
      expect(orchestrator.persistentFailureCount, 0);
    });

    test('runBurstRecovery does not call hard relogin before failure threshold', () async {
      var reconnectInvocations = 0;
      var hardReloginInvocations = 0;
      late final HubRecoveryOrchestrator orchestrator;
      final HubRecoveryRuntimeDependencies deps = HubRecoveryRuntimeDependencies(
        resilienceCoordinator: _MockHubResilienceCoordinator(),
        contextSource: _FakeHubContextSource(),
        checkHubAvailability: null,
        uiSink: _FakeHubRecoveryUiSink(),
        resilienceLogPrefix: () => '',
        isDisconnectRequested: () => false,
        tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
        attemptReconnect:
            (String serverUrl, String agentId, {String? authToken, bool recordErrorMessage = true}) async {
              reconnectInvocations++;
              orchestrator.noteTransportConnectFailureDuringRecovery();
              return false;
            },
        disconnectTransportForRecovery: () async {},
        executeHardRelogin:
            (HubConnectionContext context, {required String logSummary, bool ignoreCooldown = false}) async {
              hardReloginInvocations++;
              return null;
            },
        bumpPersistentReconnectFailure: (HubConnectionContext context, {required String reason}) {},
        isStatusError: () => false,
        cancelPersistentRetryTimer: () {},
      );
      orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: Duration.zero,
        maxReconnectDelay: Duration.zero,
        runtime: deps,
      );
      final HubConnectionContext context = deps.contextSource.resolveConnectionContext()!;
      final bool ok = await orchestrator.runBurstRecovery(
        context,
        proactiveHardReloginBeforeSocket: false,
        effectiveHardReloginRecoveryEnabled: true,
        hasAuthBridge: true,
        maxReconnectAttempts: 2,
        tokenRefreshIntervalAttempts: 2,
        recoveryEnabled: true,
        hardReloginFailureThreshold: 3,
      );

      expect(ok, isFalse);
      expect(reconnectInvocations, 2);
      expect(hardReloginInvocations, 0);
    });

    test('runBurstRecovery calls hard relogin once failure threshold is reached', () async {
      var reconnectInvocations = 0;
      var hardReloginInvocations = 0;
      late final HubRecoveryOrchestrator orchestrator;
      final HubRecoveryRuntimeDependencies deps = HubRecoveryRuntimeDependencies(
        resilienceCoordinator: _MockHubResilienceCoordinator(),
        contextSource: _FakeHubContextSource(),
        checkHubAvailability: null,
        uiSink: _FakeHubRecoveryUiSink(),
        resilienceLogPrefix: () => '',
        isDisconnectRequested: () => false,
        tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
        attemptReconnect:
            (String serverUrl, String agentId, {String? authToken, bool recordErrorMessage = true}) async {
              reconnectInvocations++;
              orchestrator.noteTransportConnectFailureDuringRecovery();
              return false;
            },
        disconnectTransportForRecovery: () async {},
        executeHardRelogin:
            (HubConnectionContext context, {required String logSummary, bool ignoreCooldown = false}) async {
              hardReloginInvocations++;
              return null;
            },
        bumpPersistentReconnectFailure: (HubConnectionContext context, {required String reason}) {},
        isStatusError: () => false,
        cancelPersistentRetryTimer: () {},
      );
      orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: Duration.zero,
        maxReconnectDelay: Duration.zero,
        runtime: deps,
      );
      final HubConnectionContext context = deps.contextSource.resolveConnectionContext()!;
      final bool ok = await orchestrator.runBurstRecovery(
        context,
        proactiveHardReloginBeforeSocket: false,
        effectiveHardReloginRecoveryEnabled: true,
        hasAuthBridge: true,
        maxReconnectAttempts: 5,
        tokenRefreshIntervalAttempts: 2,
        recoveryEnabled: true,
        hardReloginFailureThreshold: 3,
      );

      expect(ok, isFalse);
      expect(reconnectInvocations, 5);
      expect(hardReloginInvocations, 1);
    });
  });
}
