import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/bootstrap/app_shutdown_coordinator.dart';
import 'package:plug_agente/application/bootstrap/hub_connection_shutdown_registry.dart';
import 'package:plug_agente/application/ports/i_hub_connection_shutdown_port.dart';
import 'package:plug_agente/application/use_cases/apply_agent_action_on_app_exit_policies.dart';
import 'package:plug_agente/bootstrap/bootstrap_app_shutdown.dart';
import 'package:plug_agente/core/di/get_it.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:result_dart/result_dart.dart';

class _MockAgentActionTriggerScheduler extends Mock implements AgentActionTriggerScheduler {}

class _MockApplyAgentActionOnAppExitPolicies extends Mock implements ApplyAgentActionOnAppExitPolicies {}

class _MockTransportClient extends Mock implements ITransportClient {}

class _MockAutoUpdateOrchestrator extends Mock implements IAutoUpdateOrchestrator {}

class _RecordingHubShutdownPort implements IHubConnectionShutdownPort {
  _RecordingHubShutdownPort(this._events);

  final List<String> _events;

  @override
  Future<void> disconnectForShutdown() async {
    _events.add('hub_disconnect');
  }
}

void main() {
  late List<String> shutdownEvents;
  late _MockAgentActionTriggerScheduler scheduler;
  late _MockApplyAgentActionOnAppExitPolicies onAppExitPolicies;
  late HubConnectionShutdownRegistry registry;

  setUp(() async {
    await getIt.reset();
    resetShutdownStateForTesting();
    shutdownEvents = <String>[];

    scheduler = _MockAgentActionTriggerScheduler();
    onAppExitPolicies = _MockApplyAgentActionOnAppExitPolicies();
    registry = HubConnectionShutdownRegistry();
    registry.bind(_RecordingHubShutdownPort(shutdownEvents));

    when(() => scheduler.dispatchAppCloseTriggers()).thenAnswer((_) async {
      shutdownEvents.add('app_close_dispatch');
      return const Success(0);
    });
    when(() => scheduler.stop()).thenReturn(null);
    when(() => onAppExitPolicies()).thenAnswer((_) async {
      shutdownEvents.add('on_app_exit_policies');
      return const Success((queuedCancelled: 0, runningHandled: 0));
    });

    final autoUpdate = _MockAutoUpdateOrchestrator();
    when(autoUpdate.dispose).thenAnswer((_) async {
      shutdownEvents.add('auto_update_dispose');
    });

    getIt
      ..registerSingleton<HubConnectionShutdownRegistry>(registry)
      ..registerSingleton<AgentActionTriggerScheduler>(scheduler)
      ..registerSingleton<ApplyAgentActionOnAppExitPolicies>(onAppExitPolicies)
      ..registerSingleton<AppShutdownCoordinator>(
        AppShutdownCoordinator(
          hubConnectionShutdownRegistry: registry,
          transportClient: _MockTransportClient(),
          autoUpdateOrchestrator: autoUpdate,
        ),
      );
  });

  tearDown(() async {
    resetShutdownStateForTesting();
    await getIt.reset();
  });

  test('shutdownApp dispatches app-close before hub disconnect', () async {
    await shutdownApp();

    expect(
      shutdownEvents,
      <String>[
        'app_close_dispatch',
        'on_app_exit_policies',
        'auto_update_dispose',
        'hub_disconnect',
      ],
    );
    verify(() => scheduler.dispatchAppCloseTriggers()).called(1);
    verify(() => onAppExitPolicies()).called(1);
  });

  test('shutdownApp runs hub early phase exactly once', () async {
    await shutdownApp();

    expect(shutdownEvents.where((event) => event == 'hub_disconnect').length, 1);
    expect(shutdownEvents.where((event) => event == 'auto_update_dispose').length, 1);
  });
}
