import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionExecutionHistoryPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Best-effort periodic purge of terminal `agent_action_execution` rows past retention.
class AgentActionExecutionPeriodicPurge {
  AgentActionExecutionPeriodicPurge(
    AgentActionExecutionHistoryPurge purge, {
    Duration interval = ConnectionConstants.agentActionExecutionPurgeInterval,
  }) : _runner = PeriodicPurgeRunner(
         purge: () => purge(),
         interval: interval,
         logName: 'agent_action_execution_periodic_purge',
         successLogMessage: (int count) => 'Purged $count old terminal agent action execution row(s) (periodic)',
         failureLogMessage: 'Periodic agent action execution history purge failed (continuing)',
       );

  final PeriodicPurgeRunner _runner;

  bool get isRunning => _runner.isRunning;

  void start() => _runner.start();

  void stop() => _runner.stop();

  Future<void> purgeNow() => _runner.purgeNow();
}
