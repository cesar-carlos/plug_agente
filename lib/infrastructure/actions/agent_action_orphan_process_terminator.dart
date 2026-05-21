import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_execution.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_orphan_process_terminator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';

/// Terminates subprocesses that survived an agent crash before bootstrap reconciliation.
final class AgentActionOrphanProcessTerminator implements IAgentActionOrphanProcessTerminator {
  const AgentActionOrphanProcessTerminator();

  @override
  Future<bool> tryTerminateRunningProcess(AgentActionExecution execution) async {
    if (execution.status != AgentActionExecutionStatus.running) {
      return false;
    }

    final pid = execution.pid;
    if (pid == null || pid <= 0) {
      return false;
    }

    return AgentActionProcessKiller.tryKillOrphanByPid(
      executionId: execution.id,
      pid: pid,
      expectedProcessExecutable: execution.processExecutable,
      expectedProcessStartedAt: execution.processStartedAt,
    );
  }
}
