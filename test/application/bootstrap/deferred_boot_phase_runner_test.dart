import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/bootstrap/agent_actions_boot_phases.dart';
import 'package:plug_agente/application/bootstrap/deferred_boot_phase_runner.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/actions/actions.dart';

class _FakeAgentActionsBootPhases implements AgentActionsBootPhasesContract {
  _FakeAgentActionsBootPhases({
    this.onDeferredMaintenance,
    this.onStartScheduler,
    this.throwOnDeferredMaintenance = false,
    this.schedulerStarted = true,
  });

  final Future<void> Function()? onDeferredMaintenance;
  final Future<void> Function()? onStartScheduler;
  final bool throwOnDeferredMaintenance;
  final bool schedulerStarted;

  @override
  Future<void> runCritical() async {}

  @override
  Future<void> runDeferredMaintenance() async {
    if (throwOnDeferredMaintenance) {
      throw StateError('boom');
    }
    await onDeferredMaintenance?.call();
  }

  @override
  Future<bool> startSchedulerAndDispatchAppStart() async {
    await onStartScheduler?.call();
    return schedulerStarted;
  }
}

void main() {
  group('DeferredBootPhaseRunner', () {
    late AgentActionRuntimeStateGuard runtimeStateGuard;

    setUp(() async {
      await getIt.reset();
      runtimeStateGuard = AgentActionRuntimeStateGuard()..markStarting(reason: 'boot');
      getIt.registerSingleton<AgentActionRuntimeStateGuard>(runtimeStateGuard);
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('marks runtime guard ready only after deferred phases complete', () async {
      final callOrder = <String>[];
      final runner = DeferredBootPhaseRunner(
        agentActionsBootPhases: _FakeAgentActionsBootPhases(
          onDeferredMaintenance: () async {
            callOrder.add('deferred');
            expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.starting);
          },
          onStartScheduler: () async {
            callOrder.add('scheduler');
            expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.starting);
          },
        ),
      );

      final outcome = await runner.run();

      expect(callOrder, <String>['deferred', 'scheduler']);
      expect(outcome.agentActionsFullyReady, isTrue);
      expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.ready);
    });

    test('marks runtime guard disabled when deferred phases throw before scheduler', () async {
      final runner = DeferredBootPhaseRunner(
        agentActionsBootPhases: _FakeAgentActionsBootPhases(
          throwOnDeferredMaintenance: true,
        ),
      );

      final outcome = await runner.run();

      expect(outcome.hadCriticalFailure, isTrue);
      expect(outcome.shouldSkipHubAutoConnect, isTrue);
      expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.disabled);
    });

    test('marks runtime guard degraded when scheduler does not start', () async {
      final runner = DeferredBootPhaseRunner(
        agentActionsBootPhases: _FakeAgentActionsBootPhases(
          schedulerStarted: false,
        ),
      );

      final outcome = await runner.run();

      expect(outcome.hadCriticalFailure, isFalse);
      expect(outcome.schedulerStarted, isFalse);
      expect(runtimeStateGuard.snapshot.status, AgentActionSubsystemStatus.degraded);
    });
  });
}
