import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class _MockTransportClient extends Mock implements ITransportClient {}

class _MockAutoUpdateOrchestrator extends Mock implements IAutoUpdateOrchestrator {}

class _FakeHubShutdownPort implements IHubConnectionShutdownPort {
  _FakeHubShutdownPort({this.onDisconnect});

  final Future<void> Function()? onDisconnect;
  bool disconnectRequested = false;

  @override
  Future<void> disconnectForShutdown() async {
    disconnectRequested = true;
    await onDisconnect?.call();
  }
}

void main() {
  group('AppShutdownCoordinator', () {
    late HubConnectionShutdownRegistry registry;
    late _MockTransportClient transportClient;
    late _MockAutoUpdateOrchestrator autoUpdateOrchestrator;

    setUp(() {
      registry = HubConnectionShutdownRegistry();
      transportClient = _MockTransportClient();
      autoUpdateOrchestrator = _MockAutoUpdateOrchestrator();
    });

    test('runEarlyShutdownPhase disposes auto-update then disconnects bound hub port', () async {
      final callOrder = <String>[];
      when(() => autoUpdateOrchestrator.dispose()).thenAnswer((_) async {
        callOrder.add('auto-update');
      });
      final port = _FakeHubShutdownPort(
        onDisconnect: () async {
          callOrder.add('hub-port');
        },
      );
      registry.bind(port);

      final coordinator = AppShutdownCoordinator(
        hubConnectionShutdownRegistry: registry,
        transportClient: transportClient,
        autoUpdateOrchestrator: autoUpdateOrchestrator,
      );

      await coordinator.runEarlyShutdownPhase();

      expect(callOrder, <String>['auto-update', 'hub-port']);
      expect(port.disconnectRequested, isTrue);
      verify(() => autoUpdateOrchestrator.dispose()).called(1);
      verifyNever(() => transportClient.disconnect());
    });

    test('disconnectHubTransport falls back to transport when port disconnect fails', () async {
      final port = _FakeHubShutdownPort(
        onDisconnect: () async {
          throw StateError('port failed');
        },
      );
      registry.bind(port);
      when(() => transportClient.disconnect()).thenAnswer((_) async => const Success(unit));

      final coordinator = AppShutdownCoordinator(
        hubConnectionShutdownRegistry: registry,
        transportClient: transportClient,
      );

      await coordinator.disconnectHubTransport();

      verify(() => transportClient.disconnect()).called(1);
    });

    test('disconnectHubTransport uses transport when no hub port is bound', () async {
      when(() => transportClient.disconnect()).thenAnswer((_) async => const Success(unit));

      final coordinator = AppShutdownCoordinator(
        hubConnectionShutdownRegistry: registry,
        transportClient: transportClient,
      );

      await coordinator.disconnectHubTransport();

      verify(() => transportClient.disconnect()).called(1);
    });
  });
}
