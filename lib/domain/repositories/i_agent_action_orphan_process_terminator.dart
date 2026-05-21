import 'package:plug_agente/domain/actions/action_execution.dart';

/// Best-effort termination of OS processes left running after agent restart.
abstract interface class IAgentActionOrphanProcessTerminator {
  /// Returns `true` when a running process for [execution] was terminated.
  Future<bool> tryTerminateRunningProcess(AgentActionExecution execution);
}
