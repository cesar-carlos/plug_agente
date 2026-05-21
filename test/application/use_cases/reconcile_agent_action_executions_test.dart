import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/reconcile_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_orphan_process_terminator.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class _InMemoryRepository extends Fake implements IAgentActionRepository {
  final Map<String, AgentActionExecution> executions = {};

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
      if (requestedAfter != null && execution.requestedAt.isBefore(requestedAfter)) {
        return false;
      }
      return true;
    }).toList();
    if (limit != null && limit > 0 && filtered.length > limit) {
      return Success(filtered.take(limit).toList());
    }
    return Success(filtered);
  }

  @override
  Future<Result<AgentActionExecution>> saveExecution(
    AgentActionExecution execution,
  ) async {
    executions[execution.id] = execution;
    return Success(execution);
  }
}

class _MockOrphanTerminator extends Mock implements IAgentActionOrphanProcessTerminator {}

void main() {
  late _InMemoryRepository repository;
  late _MockOrphanTerminator orphanTerminator;

  setUp(() {
    repository = _InMemoryRepository();
    orphanTerminator = _MockOrphanTerminator();
    repository.executions.clear();
    registerFallbackValue(
      AgentActionExecution(
        id: 'fallback',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime.utc(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
      ),
    );
  });

  AgentActionExecution execution({
    required String id,
    required AgentActionExecutionStatus status,
    int? pid,
  }) {
    return AgentActionExecution(
      id: id,
      actionId: 'action-1',
      actionType: AgentActionType.commandLine,
      status: status,
      requestedAt: DateTime.utc(2026, 5, 15, 9),
      source: AgentActionRequestSource.scheduler,
      processStartedAt: status == AgentActionExecutionStatus.running
          ? DateTime.utc(2026, 5, 15, 9)
          : null,
      pid: pid,
      processExecutable: pid != null ? 'cmd.exe' : null,
    );
  }

  group('ReconcileAgentActionExecutions', () {
    test('should mark queued and running executions as interrupted on bootstrap', () async {
      repository.executions['queued'] = execution(
        id: 'queued',
        status: AgentActionExecutionStatus.queued,
      );
      repository.executions['running'] = execution(
        id: 'running',
        status: AgentActionExecutionStatus.running,
        pid: 1234,
      );
      when(() => orphanTerminator.tryTerminateRunningProcess(any())).thenAnswer((_) async => false);

      final useCase = ReconcileAgentActionExecutions(
        repository,
        orphanProcessTerminator: orphanTerminator,
        now: () => DateTime.utc(2026, 5, 15, 10),
      );

      final result = await useCase();
      final secondResult = await useCase();

      expect(result.getOrThrow(), 2);
      expect(secondResult.getOrThrow(), 0);
      expect(repository.executions['queued']?.status, AgentActionExecutionStatus.interrupted);
      expect(repository.executions['running']?.status, AgentActionExecutionStatus.interrupted);
      expect(
        repository.executions['running']?.failureCode,
        AgentActionFailureCode.interruptedOnBootstrap,
      );
      final captured = verify(() => orphanTerminator.tryTerminateRunningProcess(captureAny())).captured;
      expect(captured, hasLength(1));
      expect((captured.single as AgentActionExecution).id, 'running');
    });

    test('should extend failure message when orphan process was terminated', () async {
      repository.executions['running'] = execution(
        id: 'running',
        status: AgentActionExecutionStatus.running,
        pid: 4321,
      );
      when(() => orphanTerminator.tryTerminateRunningProcess(any())).thenAnswer((_) async => true);

      final useCase = ReconcileAgentActionExecutions(
        repository,
        saveExecution: SaveAgentActionExecution(repository),
        orphanProcessTerminator: orphanTerminator,
        now: () => DateTime.utc(2026, 5, 15, 10),
      );

      await useCase();

      expect(
        repository.executions['running']?.failureMessage,
        contains('Processo principal encerrado durante a reconciliacao do bootstrap'),
      );
    });
  });
}
