import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class _FakeRepository implements IAgentActionRepository {
  AgentActionExecution? lastSaved;

  @override
  Future<Result<AgentActionExecution>> saveExecution(AgentActionExecution execution) async {
    lastSaved = execution;
    return Success(execution);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  test('should persist trace and requestedBy when execution fields are empty', () async {
    final repository = _FakeRepository();
    final useCase = BackfillAgentActionExecutionCorrelation(repository);
    final execution = AgentActionExecution(
      id: 'exec-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.running,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.remoteHub,
      redactionApplied: true,
    );

    final result = await useCase(
      execution: execution,
      traceId: 'trace-from-cancel',
      requestedBy: 'hub-req-9',
    );

    expect(result.isSuccess(), isTrue);
    expect(repository.lastSaved?.traceId, 'trace-from-cancel');
    expect(repository.lastSaved?.requestedBy, 'hub-req-9');
  });

  test('should not overwrite existing correlation fields', () async {
    final repository = _FakeRepository();
    final useCase = BackfillAgentActionExecutionCorrelation(repository);
    final execution = AgentActionExecution(
      id: 'exec-1',
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.running,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.remoteHub,
      traceId: 'existing-trace',
      requestedBy: 'existing-requester',
      redactionApplied: true,
    );

    final result = await useCase(
      execution: execution,
      traceId: 'new-trace',
      requestedBy: 'new-requester',
    );

    expect(result.isSuccess(), isTrue);
    expect(repository.lastSaved, isNull);
  });
}
