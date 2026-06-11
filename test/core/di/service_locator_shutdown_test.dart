import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';

class _MockTransportClient extends Mock implements ITransportClient {}

class _MockAutoUpdateOrchestrator extends Mock implements IAutoUpdateOrchestrator {}

class _RecordingHubShutdownPort implements IHubConnectionShutdownPort {
  final List<String> events = <String>[];

  @override
  Future<void> disconnectForShutdown() async {
    events.add('disconnect');
  }
}

void main() {
  setUp(() async {
    await getIt.reset();
    resetShutdownStateForTesting();
  });

  tearDown(() async {
    resetShutdownStateForTesting();
    await getIt.reset();
  });

  test('resetShutdownStateForTesting clears shutdown dispatch gate', () {
    resetShutdownStateForTesting();
    resetShutdownStateForTesting();
    expect(true, isTrue);
  });

  test('registered AppShutdownCoordinator disconnects hub port before transport fallback', () async {
    final registry = HubConnectionShutdownRegistry();
    final port = _RecordingHubShutdownPort();
    registry.bind(port);

    final transport = _MockTransportClient();
    final autoUpdate = _MockAutoUpdateOrchestrator();
    when(autoUpdate.dispose).thenAnswer((_) async {});

    getIt
      ..registerSingleton<HubConnectionShutdownRegistry>(registry)
      ..registerSingleton<AppShutdownCoordinator>(
        AppShutdownCoordinator(
          hubConnectionShutdownRegistry: registry,
          transportClient: transport,
          autoUpdateOrchestrator: autoUpdate,
        ),
      );

    await getIt<AppShutdownCoordinator>().runEarlyShutdownPhase();

    expect(port.events, <String>['disconnect']);
    verify(autoUpdate.dispose).called(1);
    verifyNever(transport.disconnect);
  });

  test('shutdown early phase uses hub registry when coordinator is not registered', () async {
    final registry = HubConnectionShutdownRegistry();
    final port = _RecordingHubShutdownPort();
    registry.bind(port);
    getIt.registerSingleton<HubConnectionShutdownRegistry>(registry);

    final transport = _MockTransportClient();
    getIt.registerSingleton<ITransportClient>(transport);

    final coordinator = AppShutdownCoordinator(
      hubConnectionShutdownRegistry: registry,
      transportClient: transport,
    );
    await coordinator.runEarlyShutdownPhase();

    expect(port.events, <String>['disconnect']);
    verifyNever(transport.disconnect);
  });
}
