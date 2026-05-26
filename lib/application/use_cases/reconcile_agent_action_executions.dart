import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_orphan_process_terminator.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class ReconcileAgentActionExecutions {
  ReconcileAgentActionExecutions(
    this._repository, {
    SaveAgentActionExecution? saveExecution,
    DateTime Function()? now,
    IAgentActionOrphanProcessTerminator? orphanProcessTerminator,
  }) : _saveExecution = saveExecution ?? SaveAgentActionExecution(_repository),
       _now = now ?? DateTime.now,
       _orphanProcessTerminator = orphanProcessTerminator ?? const _NoOpOrphanProcessTerminator();

  static const Set<AgentActionExecutionStatus> activeBootstrapStatuses = {
    AgentActionExecutionStatus.queued,
    AgentActionExecutionStatus.running,
  };

  final IAgentActionRepository _repository;
  final SaveAgentActionExecution _saveExecution;
  final DateTime Function() _now;
  final IAgentActionOrphanProcessTerminator _orphanProcessTerminator;

  Future<Result<int>> call() async {
    final executionsResult = await _repository.listExecutions(
      statuses: activeBootstrapStatuses,
    );
    if (executionsResult.isError()) {
      return Failure(executionsResult.exceptionOrNull()!);
    }

    final now = _now();
    var reconciledCount = 0;
    for (final execution in executionsResult.getOrThrow()) {
      final orphanTerminated =
          execution.status == AgentActionExecutionStatus.running &&
          await _orphanProcessTerminator.tryTerminateRunningProcess(execution);
      const baseFailureMessage = 'Execucao interrompida porque o Plug Agente foi reiniciado antes da conclusao.';
      final saveResult = await _saveExecution(
        execution.copyWith(
          status: AgentActionExecutionStatus.interrupted,
          finishedAt: now,
          redactionApplied: true,
          failureCode: AgentActionFailureCode.interruptedOnBootstrap,
          failurePhase: AgentActionProcessConstants.bootstrapReconciliationPhase,
          failureMessage: orphanTerminated
              ? '$baseFailureMessage Processo principal encerrado durante a reconciliacao do bootstrap.'
              : baseFailureMessage,
        ),
      );
      if (saveResult.isError()) {
        return Failure(saveResult.exceptionOrNull()!);
      }
      reconciledCount++;
    }

    return Success(reconciledCount);
  }
}

final class _NoOpOrphanProcessTerminator implements IAgentActionOrphanProcessTerminator {
  const _NoOpOrphanProcessTerminator();

  @override
  Future<bool> tryTerminateRunningProcess(AgentActionExecution execution) async => false;
}
