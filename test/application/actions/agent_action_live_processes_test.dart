import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_live_processes.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class _Repository extends Mock implements IAgentActionRepository {}

void main() {
  final execution = AgentActionExecution(
    id: 'run',
    actionId: 'action',
    actionType: AgentActionType.script,
    status: AgentActionExecutionStatus.running,
    requestedAt: DateTime.utc(2026),
    source: AgentActionRequestSource.localUi,
  );
  final process = AgentActionLiveProcess(
    executionId: 'run',
    actionId: 'action',
    pid: 42,
    executable: 'script.exe',
    startedAt: DateTime.utc(2026),
    cpuLimitPercent: 50,
    readCpu: () => const Success(Duration(milliseconds: 100)),
  );
  setUpAll(() => registerFallbackValue(execution));

  test('persists identity before publishing a running process and removes it at completion', () async {
    final repo = _Repository();
    final monitor = AgentActionLiveProcesses(repo);
    when(() => repo.getExecution('run', hydrateCapturedOutput: false)).thenAnswer((_) async => Success(execution));
    when(() => repo.saveExecution(any())).thenAnswer((call) async {
      expect(monitor.forAction('action'), isEmpty);
      final saved = call.positionalArguments.single as AgentActionExecution;
      expect(saved.status, AgentActionExecutionStatus.running);
      expect(saved.pid, 42);
      expect(saved.processExecutable, 'script.exe');
      return Success(saved);
    });
    expect((await monitor.started(process)).isSuccess(), isTrue);
    expect(monitor.forAction('action').single.pid, 42);
    expect(monitor.forAction('other'), isEmpty);
    monitor.finished('run');
    expect(monitor.forAction('action'), isEmpty);
  });

  test('does not publish a process when persistence fails', () async {
    final repo = _Repository();
    final monitor = AgentActionLiveProcesses(repo);
    when(() => repo.getExecution('run', hydrateCapturedOutput: false)).thenAnswer((_) async => Success(execution));
    when(() => repo.saveExecution(any())).thenAnswer((_) async => Failure(ActionRuntimeFailure('disk failure')));
    expect((await monitor.started(process)).isError(), isTrue);
    expect(monitor.forAction('action'), isEmpty);
  });

  test('does not resurrect a terminal execution', () async {
    final repo = _Repository();
    final monitor = AgentActionLiveProcesses(repo);
    when(
      () => repo.getExecution('run', hydrateCapturedOutput: false),
    ).thenAnswer((_) async => Success(execution.copyWith(status: AgentActionExecutionStatus.killed)));
    expect((await monitor.started(process)).isError(), isTrue);
    verifyNever(() => repo.saveExecution(any()));
  });
}
