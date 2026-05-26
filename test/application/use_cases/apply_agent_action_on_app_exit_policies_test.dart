import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/apply_agent_action_on_app_exit_policies.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockRepository extends Mock implements IAgentActionRepository {}

class _MockCancel extends Mock implements CancelAgentActionExecution {}

void main() {
  late _MockRepository repository;
  late _MockCancel cancel;

  setUp(() {
    repository = _MockRepository();
    cancel = _MockCancel();
  });

  AgentActionDefinition definitionWithPolicy(AgentActionOnAppExitBehavior behavior) {
    return AgentActionDefinition(
      id: 'action-1',
      name: 'Test',
      state: AgentActionState.active,
      config: const CommandLineActionConfig(command: 'dir'),
      policies: AgentActionDefinitionPolicies(
        lifecycle: AgentActionLifecyclePolicy(onAppExit: behavior),
      ),
    );
  }

  AgentActionExecution execution({
    required String id,
    required AgentActionExecutionStatus status,
  }) {
    return AgentActionExecution(
      id: id,
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: status,
      requestedAt: DateTime.utc(2026, 5, 18, 12),
      source: AgentActionRequestSource.localUi,
      redactionApplied: true,
    );
  }

  group('ApplyAgentActionOnAppExitPolicies', () {
    test('should cancel queued executions and kill running when policy is killMainProcess', () async {
      when(
        () => repository.listExecutions(
          statuses: const {AgentActionExecutionStatus.queued},
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => Success([execution(id: 'q1', status: AgentActionExecutionStatus.queued)]),
      );
      when(
        () => repository.listExecutions(
          statuses: const {AgentActionExecutionStatus.running},
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => Success([execution(id: 'r1', status: AgentActionExecutionStatus.running)]),
      );
      when(() => repository.getDefinition('action-1')).thenAnswer(
        (_) async => Success(definitionWithPolicy(AgentActionOnAppExitBehavior.killMainProcess)),
      );
      when(() => cancel('q1')).thenAnswer(
        (_) async => Success(execution(id: 'q1', status: AgentActionExecutionStatus.cancelled)),
      );
      when(() => cancel('r1')).thenAnswer(
        (_) async => Success(execution(id: 'r1', status: AgentActionExecutionStatus.killed)),
      );

      final useCase = ApplyAgentActionOnAppExitPolicies(repository, cancel);
      final result = await useCase();

      expect(result.isSuccess(), isTrue);
      final counts = result.getOrThrow();
      expect(counts.queuedCancelled, 1);
      expect(counts.runningHandled, 1);
      verify(() => cancel('q1')).called(1);
      verify(() => cancel('r1')).called(1);
    });

    test('should skip running cancel when policy is leaveRunning', () async {
      when(
        () => repository.listExecutions(
          statuses: const {AgentActionExecutionStatus.queued},
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => const Success([]));
      when(
        () => repository.listExecutions(
          statuses: const {AgentActionExecutionStatus.running},
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => Success([execution(id: 'r1', status: AgentActionExecutionStatus.running)]),
      );
      when(() => repository.getDefinition('action-1')).thenAnswer(
        (_) async => Success(definitionWithPolicy(AgentActionOnAppExitBehavior.leaveRunning)),
      );

      final useCase = ApplyAgentActionOnAppExitPolicies(repository, cancel);
      final result = await useCase();

      expect(result.getOrThrow().runningHandled, 0);
      verifyNever(() => cancel(any()));
    });

    test('should wait then kill running when policy is waitThenKillMainProcess', () async {
      when(
        () => repository.listExecutions(
          statuses: const {AgentActionExecutionStatus.queued},
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => const Success([]));
      when(
        () => repository.listExecutions(
          statuses: const {AgentActionExecutionStatus.running},
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => Success([execution(id: 'r1', status: AgentActionExecutionStatus.running)]),
      );
      when(() => repository.getDefinition('action-1')).thenAnswer(
        (_) async => const Success(
          AgentActionDefinition(
            id: 'action-1',
            name: 'Test',
            state: AgentActionState.active,
            config: CommandLineActionConfig(command: 'dir'),
            policies: AgentActionDefinitionPolicies(
              lifecycle: AgentActionLifecyclePolicy(
                onAppExit: AgentActionOnAppExitBehavior.waitThenKillMainProcess,
                waitBeforeKillOnAppExit: Duration(milliseconds: 30),
              ),
            ),
          ),
        ),
      );
      when(() => cancel('r1')).thenAnswer(
        (_) async => Success(execution(id: 'r1', status: AgentActionExecutionStatus.killed)),
      );

      final useCase = ApplyAgentActionOnAppExitPolicies(repository, cancel);
      final stopwatch = Stopwatch()..start();
      final result = await useCase();
      stopwatch.stop();

      expect(result.getOrThrow().runningHandled, 1);
      expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 30)));
      verify(() => cancel('r1')).called(1);
    });
  });
}
