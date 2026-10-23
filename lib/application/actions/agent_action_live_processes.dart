import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_process_observer.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

export 'package:plug_agente/domain/actions/i_agent_action_process_observer.dart' show AgentActionLiveProcess;

/// Publishes identities only after their durable running record is updated.
class AgentActionLiveProcesses implements IAgentActionProcessObserver {
  AgentActionLiveProcesses(this._repository);
  final IAgentActionRepository _repository;
  final Map<String, AgentActionLiveProcess> _active = {};

  List<AgentActionLiveProcess> forAction(String actionId) =>
      _active.values.where((process) => process.actionId == actionId).toList(growable: false);

  @override
  Future<Result<void>> started(AgentActionLiveProcess process) async {
    final found = await _repository.getExecution(process.executionId, hydrateCapturedOutput: false);
    if (found.isError()) return Failure(found.exceptionOrNull()!);
    final execution = found.getOrThrow();
    if (execution.actionId != process.actionId || execution.status != AgentActionExecutionStatus.running) {
      return Failure(ActionRuntimeFailure('A execução deixou de estar ativa antes de iniciar o processo.'));
    }
    final saved = await _repository.saveExecution(
      execution.copyWith(
        pid: process.pid,
        processExecutable: process.executable,
        processStartedAt: process.startedAt,
      ),
    );
    if (saved.isError()) return Failure(saved.exceptionOrNull()!);
    _active[process.executionId] = process;
    return const Success(unit);
  }

  @override
  void finished(String executionId) => _active.remove(executionId);
}
