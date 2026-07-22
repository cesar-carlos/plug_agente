import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/hub_recovery_ui_sink.dart';
import 'package:plug_agente/application/services/hub_resilience_coordinator.dart';
import 'package:plug_agente/application/services/hub_transport_lifecycle_coordinator.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/domain/value_objects/hub_recovery_ui_hint.dart';

class _MockHubResilienceCoordinator extends Mock implements HubResilienceCoordinator {}

class _RecordingUiSink implements HubRecoveryUiSink {
  HubRecoveryUiHint hint = HubRecoveryUiHint.none;

  @override
  void clearHubRecoveryUiHint() {
    hint = HubRecoveryUiHint.none;
  }

  @override
  void setHubRecoveryUiHint(HubRecoveryUiHint value) {
    hint = value;
  }
}

HubTransportLifecycleRuntimeDependencies _runtimeDeps({
  required _MockHubResilienceCoordinator resilience,
  required _RecordingUiSink uiSink,
  required String Function() statusName,
  required bool Function() isDisconnectRequested,
  void Function({required bool clearError})? enterReconnecting,
  void Function()? enterConnected,
  void Function()? startProactiveTokenRefreshSchedule,
  void Function({required String trigger})? kickHubTransportRecovery,
}) {
  return HubTransportLifecycleRuntimeDependencies(
    resilienceCoordinator: resilience,
    uiSink: uiSink,
    resilienceLogPrefix: () => '',
    lastAgentId: () => 'agent-1',
    connectionStatusName: statusName,
    isDisconnectRequested: isDisconnectRequested,
    isDisconnected: () => statusName() == 'disconnected',
    isNegotiating: () => statusName() == 'negotiating',
    isReconnecting: () => statusName() == 'reconnecting',
    isConnected: () => statusName() == 'connected',
    isConnectedOrNegotiating: () {
      final status = statusName();
      return status == 'connected' || status == 'negotiating';
    },
    hasPersistentRetryTimer: () => false,
    persistentRetryInFlight: () => false,
    enterReconnecting: enterReconnecting ?? ({required bool clearError}) {},
    enterConnected: enterConnected ?? () {},
    kickHubTransportRecovery: kickHubTransportRecovery ?? ({required String trigger}) {},
    schedulePersistentRetryTick: () {},
    cancelPersistentRetryTimer: () {},
    startProactiveTokenRefreshSchedule: startProactiveTokenRefreshSchedule ?? () {},
  );
}

void main() {
  group('HubTransportLifecycleCoordinator', () {
    test('enters connected state on protocol ready', () {
      final resilience = _MockHubResilienceCoordinator();
      final uiSink = _RecordingUiSink();
      var status = 'negotiating';
      var connected = false;
      var proactiveRefreshStarted = false;

      final coordinator = HubTransportLifecycleCoordinator(
        runtime: _runtimeDeps(
          resilience: resilience,
          uiSink: uiSink,
          statusName: () => status,
          isDisconnectRequested: () => false,
          enterConnected: () {
            status = 'connected';
            connected = true;
          },
          startProactiveTokenRefreshSchedule: () => proactiveRefreshStarted = true,
        ),
      );

      coordinator.handle(const HubProtocolReady());

      verify(resilience.cancelNegotiatingWatchdog).called(1);
      verify(resilience.clearResilienceRecovery).called(1);
      expect(status, 'connected');
      expect(connected, isTrue);
      expect(proactiveRefreshStarted, isTrue);
      expect(uiSink.hint, HubRecoveryUiHint.none);
    });

    test('ignores lifecycle events after disconnect was requested', () {
      final resilience = _MockHubResilienceCoordinator();
      var status = 'connected';

      final coordinator = HubTransportLifecycleCoordinator(
        runtime: _runtimeDeps(
          resilience: resilience,
          uiSink: _RecordingUiSink(),
          statusName: () => status,
          isDisconnectRequested: () => true,
          enterReconnecting: ({required bool clearError}) => status = 'reconnecting',
        ),
      );

      coordinator.handle(const HubTransportDisconnected(reason: 'transport close'));

      verifyNever(resilience.beginResilienceRecovery);
      expect(status, 'connected');
    });

    test('client_or_network disconnect updates UI but does not kick burst recovery', () {
      final resilience = _MockHubResilienceCoordinator();
      var status = 'connected';
      final kickedTriggers = <String>[];

      final coordinator = HubTransportLifecycleCoordinator(
        runtime: _runtimeDeps(
          resilience: resilience,
          uiSink: _RecordingUiSink(),
          statusName: () => status,
          isDisconnectRequested: () => false,
          enterReconnecting: ({required bool clearError}) => status = 'reconnecting',
          kickHubTransportRecovery: ({required String trigger}) => kickedTriggers.add(trigger),
        ),
      );

      coordinator.handle(const HubTransportDisconnected(reason: 'transport close'));

      verify(resilience.beginResilienceRecovery).called(1);
      expect(status, 'reconnecting');
      expect(kickedTriggers, isEmpty);
    });

    test('io_server_disconnect kicks app recovery immediately', () {
      final resilience = _MockHubResilienceCoordinator();
      var status = 'connected';
      final kickedTriggers = <String>[];

      final coordinator = HubTransportLifecycleCoordinator(
        runtime: _runtimeDeps(
          resilience: resilience,
          uiSink: _RecordingUiSink(),
          statusName: () => status,
          isDisconnectRequested: () => false,
          enterReconnecting: ({required bool clearError}) => status = 'reconnecting',
          kickHubTransportRecovery: ({required String trigger}) => kickedTriggers.add(trigger),
        ),
      );

      coordinator.handle(const HubTransportDisconnected(reason: 'io server disconnect'));

      verify(resilience.beginResilienceRecovery).called(1);
      expect(status, 'reconnecting');
      expect(kickedTriggers, ['hub_transport_io_server_disconnect']);
    });
  });
}
