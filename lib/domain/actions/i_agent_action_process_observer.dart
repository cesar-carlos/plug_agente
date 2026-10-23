import 'package:result_dart/result_dart.dart';

typedef AgentActionCpuReader = Result<Duration> Function();

class AgentActionLiveProcess {
  AgentActionLiveProcess({
    required this.executionId,
    required this.actionId,
    required this.pid,
    required this.executable,
    required this.startedAt,
    required this.readCpu,
    required this.cpuLimitPercent,
  });
  final String executionId;
  final String actionId;
  final int pid;
  final String executable;
  final DateTime startedAt;
  final int cpuLimitPercent;

  /// Cumulative CPU time of the Windows job, including its descendants.
  final AgentActionCpuReader readCpu;
}

abstract interface class IAgentActionProcessObserver {
  Future<Result<void>> started(AgentActionLiveProcess process);
  void finished(String executionId);
}
