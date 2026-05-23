import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/i_connection_context_source.dart';
import 'package:plug_agente/application/ports/i_hub_recovery_auth_bridge.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/core/utils/async_operation_gate.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_errors;
import 'package:plug_agente/domain/value_objects/hub_connection_context.dart';
import 'package:result_dart/result_dart.dart';

class _MockConnectionContextSource extends Mock implements IConnectionContextSource {}

class _MockRecoveryAuthBridge extends Mock implements IHubRecoveryAuthBridge {}

const _context = HubConnectionContext(
  configId: 'cfg-1',
  serverUrl: 'https://hub.test',
  agentId: 'agent-1',
);

HubResilienceEnvironment _environment({
  bool Function()? isDisconnectRequested,
  bool Function()? isReconnecting,
  bool Function()? hasPersistentRetryTimer,
  bool Function()? persistentRetryInFlight,
  bool Function()? isNegotiating,
  HubConnectionContext? Function()? resolveConnectionContext,
  String? Function()? lastAgentId,
  void Function(String? recoveryId)? syncTransportResilienceLogContext,
  Future<void> Function()? handleReconnectionNeeded,
  void Function({required int timeoutMs})? onNegotiatingWatchdogTimeoutWithoutContext,
  void Function()? onNegotiatingWatchdogTimeoutWithContext,
}) {
  return HubResilienceEnvironment(
    isDisconnectRequested: isDisconnectRequested ?? () => false,
    isReconnecting: isReconnecting ?? () => false,
    hasPersistentRetryTimer: hasPersistentRetryTimer ?? () => false,
    persistentRetryInFlight: persistentRetryInFlight ?? () => false,
    isNegotiating: isNegotiating ?? () => false,
    resolveConnectionContext: resolveConnectionContext ?? () => null,
    lastAgentId: lastAgentId ?? () => null,
    syncTransportResilienceLogContext: syncTransportResilienceLogContext ?? (_) {},
    handleReconnectionNeeded: handleReconnectionNeeded ?? () async {},
    onNegotiatingWatchdogTimeoutWithoutContext:
        onNegotiatingWatchdogTimeoutWithoutContext ?? ({required int timeoutMs}) {},
    onNegotiatingWatchdogTimeoutWithContext: onNegotiatingWatchdogTimeoutWithContext ?? () {},
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const AuthToken(token: 'token', refreshToken: 'refresh'));
  });

  group('HubResilienceCoordinator', () {
    test('should assign recovery id and sync transport log context once per cycle', () {
      String? syncedId;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          syncTransportResilienceLogContext: (id) => syncedId = id,
        ),
      );

      expect(coordinator.recoveryId, isNull);
      coordinator.beginResilienceRecovery();
      expect(coordinator.recoveryId, isNotEmpty);
      expect(syncedId, coordinator.recoveryId);

      final firstId = coordinator.recoveryId;
      coordinator.beginResilienceRecovery();
      expect(coordinator.recoveryId, firstId);

      coordinator.clearResilienceRecovery();
      expect(coordinator.recoveryId, isNull);
      expect(syncedId, isNull);
    });

    test('should serialize hub connect through injected AsyncOperationGate', () async {
      final gate = AsyncOperationGate();
      var inFlight = 0;
      var maxConcurrent = 0;
      Completer<void>? firstGate;

      final coordinator = HubResilienceCoordinator(
        environment: _environment(),
        hubConnectGate: gate,
      );

      Future<int> runConnect() {
        return coordinator.runSerializedHubConnect(() async {
          inFlight++;
          if (inFlight > maxConcurrent) {
            maxConcurrent = inFlight;
          }
          firstGate ??= Completer<void>();
          await firstGate!.future;
          inFlight--;
          return 1;
        }, staleResult: 0);
      }

      final first = runConnect();
      while (firstGate == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final second = runConnect();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(maxConcurrent, 1);

      firstGate?.complete();
      await Future.wait([first, second]);
      expect(maxConcurrent, 1);
    });

    test('should abort serialized hub connect when disconnect is requested', () async {
      var disconnectRequested = false;
      var actionRan = false;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(isDisconnectRequested: () => disconnectRequested),
      );

      disconnectRequested = true;
      final result = await coordinator.runSerializedHubConnect(
        () async {
          actionRan = true;
          return 'ran';
        },
        staleResult: 'stale',
      );

      expect(result, 'stale');
      expect(actionRan, isFalse);
    });

    test('should coalesce exclusive recovery schedules through injected gate', () async {
      final recoveryGate = ExclusiveRecoveryGate();
      var handlerRuns = 0;
      Completer<void>? handlerGate;

      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          handleReconnectionNeeded: () async {
            handlerRuns++;
            handlerGate ??= Completer<void>();
            await handlerGate!.future;
          },
        ),
        recoveryGate: recoveryGate,
      );

      unawaited(coordinator.scheduleExclusiveRecovery());
      unawaited(coordinator.scheduleExclusiveRecovery());

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handlerRuns, 1);

      handlerGate?.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handlerRuns, 1);
    });

    test('should skip kickHubTransportRecovery when burst recovery is in flight', () async {
      var handlerRuns = 0;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          isReconnecting: () => true,
          handleReconnectionNeeded: () async {
            handlerRuns++;
          },
        ),
      );

      coordinator.kickHubTransportRecovery(trigger: 'test');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handlerRuns, 0);
    });

    test('should route kickHubTransportRecovery into exclusive recovery handler', () async {
      var handlerRuns = 0;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          handleReconnectionNeeded: () async {
            handlerRuns++;
          },
        ),
      );

      coordinator.kickHubTransportRecovery(trigger: 'hub_transport_disconnected');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(handlerRuns, 1);
    });

    test('should fire negotiating watchdog timeout without context callback', () async {
      var capturedTimeoutMs = 0;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          isNegotiating: () => true,
          onNegotiatingWatchdogTimeoutWithoutContext: ({required int timeoutMs}) {
            capturedTimeoutMs = timeoutMs;
          },
        ),
        capabilitiesNegotiationWatchdogOverride: const Duration(milliseconds: 20),
      );

      coordinator.armNegotiatingWatchdog();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(capturedTimeoutMs, 20);
    });

    test('should fire negotiating watchdog timeout with context and schedule recovery', () async {
      var withContextCalled = false;
      var handlerRuns = 0;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          isNegotiating: () => true,
          resolveConnectionContext: () => const HubConnectionContext(
            configId: 'cfg-1',
            serverUrl: 'https://hub.test',
            agentId: 'agent-1',
          ),
          onNegotiatingWatchdogTimeoutWithContext: () {
            withContextCalled = true;
          },
          handleReconnectionNeeded: () async {
            handlerRuns++;
          },
        ),
        capabilitiesNegotiationWatchdogOverride: const Duration(milliseconds: 20),
      );

      coordinator.armNegotiatingWatchdog();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(withContextCalled, isTrue);
      expect(coordinator.recoveryId, isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(handlerRuns, 1);
    });

    test('should cancel negotiating watchdog on dispose', () async {
      var handlerRuns = 0;
      final coordinator = HubResilienceCoordinator(
        environment: _environment(
          isNegotiating: () => true,
          handleReconnectionNeeded: () async {
            handlerRuns++;
          },
        ),
        capabilitiesNegotiationWatchdogOverride: const Duration(milliseconds: 30),
      );

      coordinator.armNegotiatingWatchdog();
      coordinator.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handlerRuns, 0);
    });

    test('should resolve connection context from injected source', () {
      final contextSource = _MockConnectionContextSource();
      when(contextSource.resolveConnectionContext).thenReturn(_context);

      final coordinator = HubResilienceCoordinator(
        environment: _environment(),
        connectionContextSource: contextSource,
      );

      expect(coordinator.resolveConnectionContext(), _context);
    });

    test('should refresh token through recovery auth bridge', () async {
      final bridge = _MockRecoveryAuthBridge();
      when(() => bridge.currentTokenForConfig('cfg-1')).thenReturn(
        const AuthToken(token: 'old-token', refreshToken: 'refresh'),
      );
      when(
        () => bridge.refreshSession(
          'https://hub.test',
          configId: 'cfg-1',
          currentToken: any(named: 'currentToken'),
        ),
      ).thenAnswer(
        (_) async => const Success(AuthToken(token: 'new-token', refreshToken: 'refresh-2')),
      );

      final coordinator = HubResilienceCoordinator(
        environment: _environment(),
        recoveryAuthBridge: bridge,
        tokenRefreshMinInterval: Duration.zero,
      );

      final result = await coordinator.tryRefreshToken(_context);

      expect(result.kind, TokenRefreshResultKind.refreshed);
      expect(result.token, 'new-token');
      verify(() => bridge.restoreToken(any(), configId: 'cfg-1', silent: true)).called(1);
    });

    test('should execute hard relogin through recovery auth bridge', () async {
      final bridge = _MockRecoveryAuthBridge();
      when(() => bridge.logout(configId: 'cfg-1')).thenAnswer((_) async {});
      when(
        () => bridge.loginWithStoredCredentials(
          'https://hub.test',
          'agent-1',
          configId: 'cfg-1',
        ),
      ).thenAnswer(
        (_) async => const Success(AuthToken(token: 'relogin-token', refreshToken: 'refresh-3')),
      );

      final coordinator = HubResilienceCoordinator(
        environment: _environment(),
        recoveryAuthBridge: bridge,
      );

      final result = await coordinator.executeHardRelogin(
        _context,
        logSummary: 'trigger=test',
        hardReloginCooldown: Duration.zero,
        ignoreCooldown: true,
      );

      expect(result.outcome, HardReloginOutcome.success);
      expect(result.token, 'relogin-token');
      verify(() => bridge.logout(configId: 'cfg-1')).called(1);
      verify(() => bridge.restoreToken(any(), configId: 'cfg-1', silent: true)).called(1);
    });

    test('should map hard relogin failure to recovery error', () async {
      final bridge = _MockRecoveryAuthBridge();
      when(() => bridge.logout(configId: 'cfg-1')).thenAnswer((_) async {});
      when(
        () => bridge.loginWithStoredCredentials(
          'https://hub.test',
          'agent-1',
          configId: 'cfg-1',
        ),
      ).thenAnswer((_) async => Failure(domain_errors.ConfigurationFailure('Invalid credentials')));
      when(() => bridge.clearStoredSession('cfg-1')).thenAnswer((_) async {});

      final coordinator = HubResilienceCoordinator(
        environment: _environment(),
        recoveryAuthBridge: bridge,
      );

      final result = await coordinator.executeHardRelogin(
        _context,
        logSummary: 'trigger=test',
        hardReloginCooldown: Duration.zero,
        ignoreCooldown: true,
      );

      expect(result.outcome, HardReloginOutcome.failed);
      verify(() => bridge.setRecoveryError(any())).called(1);
    });
  });
}
