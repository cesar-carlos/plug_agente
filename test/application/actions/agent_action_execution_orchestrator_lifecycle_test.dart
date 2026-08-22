import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_execution_orchestrator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

void main() {
  late _InMemoryExecutionRepository repository;

  setUp(() {
    repository = _InMemoryExecutionRepository();
  });

  AgentActionDefinition definition() {
    return const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'dir'),
    );
  }

  group('AgentActionExecutionOrchestrator lifecycle', () {
    test('should persist cancelled status when runner reports executionCancelled', () async {
      final runner = _ControlledRunner();
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final resultFuture = orchestrator.run(
        gatedContext: AgentActionGatedExecutionContext(
          definition: definition(),
          runner: runner,
        ),
        request: const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await runner.waitForStart();
      runner.completions.first.complete(
        Failure(
          ActionRuntimeFailure.withContext(
            message: 'Elevated execution was cancelled before completion.',
            code: AgentActionFailureCode.executionCancelled,
            context: const {
              'user_message': 'A execucao elevada foi cancelada.',
            },
          ),
        ),
      );

      final result = await resultFuture;
      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.cancelled);
      expect(result.getOrThrow().failureCode, AgentActionFailureCode.executionCancelled);
    });

    test('should start only one runner for concurrent identical idempotency keys', () async {
      final runner = _ControlledRunner();
      final orchestrator = AgentActionExecutionOrchestrator(
        repository,
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );
      const request = AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'same-key',
      );
      final gated = AgentActionGatedExecutionContext(
        definition: definition(),
        runner: runner,
      );

      final first = orchestrator.run(gatedContext: gated, request: request);
      final second = orchestrator.run(gatedContext: gated, request: request);
      await runner.waitForStart();
      expect(runner.startedCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      final results = await Future.wait([first, second]);
      expect(results[0].isSuccess(), isTrue);
      expect(results[1].isSuccess(), isTrue);
      expect(results[0].getOrThrow().id, results[1].getOrThrow().id);
      expect(runner.startedCount, 1);
    });
  });
}

class _InMemoryExecutionRepository extends Fake implements IAgentActionRepository {
  final Map<String, AgentActionExecution> executions = {};

  @override
  Future<Result<AgentActionExecution>> saveExecution(AgentActionExecution execution) async {
    executions[execution.id] = execution;
    return Success(execution);
  }

  @override
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    final filtered = executions.values.where((execution) {
      if (actionId != null && execution.actionId != actionId) {
        return false;
      }
      if (idempotencyKey != null && execution.idempotencyKey != idempotencyKey) {
        return false;
      }
      if (statuses != null && !statuses.contains(execution.status)) {
        return false;
      }
      return true;
    }).toList();
    if (limit != null && limit > 0 && filtered.length > limit) {
      return Success(filtered.take(limit).toList());
    }
    return Success(filtered);
  }
}

class _ControlledRunner implements AgentActionLocalRunner {
  final List<Completer<Result<AgentActionProcessResult>>> completions = [];
  final List<Completer<void>> starts = [];

  int get startedCount => starts.length;

  Future<void> waitForStart() async {
    while (starts.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    starts.add(Completer<void>()..complete());
    final completion = Completer<Result<AgentActionProcessResult>>();
    completions.add(completion);
    return completion.future;
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: expectedPid,
        message: 'Processo principal finalizado.',
      ),
    );
  }
}
