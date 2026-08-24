import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
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
    attemptReconnect: (serverUrl, agentId, {authToken, recordErrorMessage = true}) async =>
        false,
    disconnectTransportForRecovery: () async {},
    executeHardRelogin:
        (context, {required logSummary, ignoreCooldown = false}) async => null,
    bumpPersistentReconnectFailure: (context, {required reason}) {},
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
      final deps = HubRecoveryRuntimeDependencies(
        resilienceCoordinator: _MockHubResilienceCoordinator(),
        contextSource: _FakeHubContextSource(),
        checkHubAvailability: null,
        uiSink: _FakeHubRecoveryUiSink(),
        resilienceLogPrefix: () => '',
        isDisconnectRequested: () => false,
        tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
        attemptReconnect:
            (serverUrl, agentId, {authToken, recordErrorMessage = true}) async {
              reconnectInvocations++;
              orchestrator.noteTransportConnectFailureDuringRecovery();
              return false;
            },
        disconnectTransportForRecovery: () async {},
        executeHardRelogin:
            (context, {required logSummary, ignoreCooldown = false}) async {
              hardReloginInvocations++;
              return null;
            },
        bumpPersistentReconnectFailure: (context, {required reason}) {},
        isStatusError: () => false,
        cancelPersistentRetryTimer: () {},
      );
      orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: Duration.zero,
        maxReconnectDelay: Duration.zero,
        runtime: deps,
      );
      final context = deps.contextSource.resolveConnectionContext()!;
      final ok = await orchestrator.runBurstRecovery(
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
      final deps = HubRecoveryRuntimeDependencies(
        resilienceCoordinator: _MockHubResilienceCoordinator(),
        contextSource: _FakeHubContextSource(),
        checkHubAvailability: null,
        uiSink: _FakeHubRecoveryUiSink(),
        resilienceLogPrefix: () => '',
        isDisconnectRequested: () => false,
        tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
        attemptReconnect:
            (serverUrl, agentId, {authToken, recordErrorMessage = true}) async {
              reconnectInvocations++;
              orchestrator.noteTransportConnectFailureDuringRecovery();
              return false;
            },
        disconnectTransportForRecovery: () async {},
        executeHardRelogin:
            (context, {required logSummary, ignoreCooldown = false}) async {
              hardReloginInvocations++;
              return null;
            },
        bumpPersistentReconnectFailure: (context, {required reason}) {},
        isStatusError: () => false,
        cancelPersistentRetryTimer: () {},
      );
      orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: Duration.zero,
        maxReconnectDelay: Duration.zero,
        runtime: deps,
      );
      final context = deps.contextSource.resolveConnectionContext()!;
      final ok = await orchestrator.runBurstRecovery(
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

    test(
      'runPersistentTick bumps persistent failure when hard relogin fails transiently',
      () async {
        var bumpFailureCalls = 0;
        String? bumpReason;
        late final HubRecoveryOrchestrator orchestrator;
        final deps = HubRecoveryRuntimeDependencies(
          resilienceCoordinator: _MockHubResilienceCoordinator(),
          contextSource: _FakeHubContextSource(),
          checkHubAvailability: null,
          uiSink: _FakeHubRecoveryUiSink(),
          resilienceLogPrefix: () => '',
          isDisconnectRequested: () => false,
          tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
          attemptReconnect:
              (serverUrl, agentId, {authToken, recordErrorMessage = true}) async {
                orchestrator.noteTransportConnectFailureDuringRecovery();
                return false;
              },
          disconnectTransportForRecovery: () async {},
          executeHardRelogin:
              (context, {required logSummary, ignoreCooldown = false}) async => null,
          bumpPersistentReconnectFailure: (context, {required reason}) {
            bumpFailureCalls++;
            bumpReason = reason;
          },
          isStatusError: () => false,
          cancelPersistentRetryTimer: () {},
        );
        orchestrator = HubRecoveryOrchestrator(
          initialReconnectDelay: Duration.zero,
          maxReconnectDelay: Duration.zero,
          runtime: deps,
        );
        orchestrator.consecutiveReconnectFailures = 3;

        await orchestrator.runPersistentTick(
          tokenRefreshIntervalAttempts: 2,
          recoveryEnabled: true,
          hardReloginFailureThreshold: 3,
        );

        expect(bumpFailureCalls, 1);
        expect(bumpReason, TransportReconnectConstants.socketReconnectFailedReason);
      },
    );

    test(
      'runPersistentTick stops without bumping failure when hard relogin fails permanently',
      () async {
        var bumpFailureCalls = 0;
        late final HubRecoveryOrchestrator orchestrator;
        final deps = HubRecoveryRuntimeDependencies(
          resilienceCoordinator: _MockHubResilienceCoordinator(),
          contextSource: _FakeHubContextSource(),
          checkHubAvailability: null,
          uiSink: _FakeHubRecoveryUiSink(),
          resilienceLogPrefix: () => '',
          isDisconnectRequested: () => false,
          tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
          attemptReconnect:
              (serverUrl, agentId, {authToken, recordErrorMessage = true}) async {
                orchestrator.noteTransportConnectFailureDuringRecovery();
                return false;
              },
          disconnectTransportForRecovery: () async {},
          executeHardRelogin:
              (context, {required logSummary, ignoreCooldown = false}) async => null,
          bumpPersistentReconnectFailure: (context, {required reason}) {
            bumpFailureCalls++;
          },
          isStatusError: () => true,
          cancelPersistentRetryTimer: () {},
        );
        orchestrator = HubRecoveryOrchestrator(
          initialReconnectDelay: Duration.zero,
          maxReconnectDelay: Duration.zero,
          runtime: deps,
        );
        orchestrator.consecutiveReconnectFailures = 3;

        await orchestrator.runPersistentTick(
          tokenRefreshIntervalAttempts: 2,
          recoveryEnabled: true,
          hardReloginFailureThreshold: 3,
        );

        expect(bumpFailureCalls, 0);
      },
    );

    test('runBurstRecovery does not reconnect when disconnect is requested during delay', () {
      fakeAsync((async) {
        var reconnectInvocations = 0;
        var disconnectRequested = false;
        late final HubRecoveryOrchestrator orchestrator;
        final deps = HubRecoveryRuntimeDependencies(
          resilienceCoordinator: _MockHubResilienceCoordinator(),
          contextSource: _FakeHubContextSource(),
          checkHubAvailability: null,
          uiSink: _FakeHubRecoveryUiSink(),
          resilienceLogPrefix: () => '',
          isDisconnectRequested: () => disconnectRequested,
          tryRefreshToken: (_) async => const TokenRefreshResult.skippedByCooldown(),
          attemptReconnect: (serverUrl, agentId, {authToken, recordErrorMessage = true}) async {
            reconnectInvocations++;
            return true;
          },
          disconnectTransportForRecovery: () async {},
          executeHardRelogin: (context, {required logSummary, ignoreCooldown = false}) async => null,
          bumpPersistentReconnectFailure: (context, {required reason}) {},
          isStatusError: () => false,
          cancelPersistentRetryTimer: () {},
        );
        orchestrator = HubRecoveryOrchestrator(
          initialReconnectDelay: const Duration(seconds: 1),
          maxReconnectDelay: const Duration(seconds: 1),
          runtime: deps,
        );
        final context = deps.contextSource.resolveConnectionContext()!;
        var recovered = false;
        unawaited(
          orchestrator
              .runBurstRecovery(
                context,
                proactiveHardReloginBeforeSocket: false,
                effectiveHardReloginRecoveryEnabled: false,
                hasAuthBridge: false,
                maxReconnectAttempts: 3,
                tokenRefreshIntervalAttempts: 10,
                recoveryEnabled: false,
                hardReloginFailureThreshold: 99,
              )
              .then((value) => recovered = value),
        );
        async.flushMicrotasks();
        disconnectRequested = true;
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(recovered, isFalse);
        expect(reconnectInvocations, 0);
      });
    });

    test('runPersistentTick cancels timer on terminal token refresh', () async {
      var cancelTimerCalls = 0;
      var reconnectInvocations = 0;
      late final HubRecoveryOrchestrator orchestrator;
      final deps = HubRecoveryRuntimeDependencies(
        resilienceCoordinator: _MockHubResilienceCoordinator(),
        contextSource: _FakeHubContextSource(),
        checkHubAvailability: null,
        uiSink: _FakeHubRecoveryUiSink(),
        resilienceLogPrefix: () => '',
        isDisconnectRequested: () => false,
        tryRefreshToken: (_) async => const TokenRefreshResult.terminalFailure(),
        attemptReconnect: (serverUrl, agentId, {authToken, recordErrorMessage = true}) async {
          reconnectInvocations++;
          return false;
        },
        disconnectTransportForRecovery: () async {},
        executeHardRelogin: (context, {required logSummary, ignoreCooldown = false}) async => null,
        bumpPersistentReconnectFailure: (context, {required reason}) {},
        isStatusError: () => false,
        cancelPersistentRetryTimer: () => cancelTimerCalls++,
      );
      orchestrator = HubRecoveryOrchestrator(
        initialReconnectDelay: Duration.zero,
        maxReconnectDelay: Duration.zero,
        runtime: deps,
      );

      await orchestrator.runPersistentTick(
        tokenRefreshIntervalAttempts: 1,
        recoveryEnabled: true,
        hardReloginFailureThreshold: 3,
      );

      expect(cancelTimerCalls, 1);
      expect(reconnectInvocations, 0);
    });
  });
}
