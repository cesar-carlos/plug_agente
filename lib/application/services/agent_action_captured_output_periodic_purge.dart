import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionCapturedOutputPurge = Future<Result<int>> Function({DateTime? now});

/// Best-effort periodic purge of stored stdout/stderr on old terminal executions.
class AgentActionCapturedOutputPeriodicPurge {
  AgentActionCapturedOutputPeriodicPurge(
    AgentActionCapturedOutputPurge purge, {
    Duration interval = ConnectionConstants.agentActionCapturedOutputPurgeInterval,
  }) : _runner = PeriodicPurgeRunner(
          purge: () => purge(),
          interval: interval,
          logName: 'agent_action_captured_output_periodic_purge',
          successLogMessage: (int count) =>
              'Cleared captured output on $count agent action execution row(s) (periodic)',
          failureLogMessage: 'Periodic agent action captured output purge failed (continuing)',
        );

  final PeriodicPurgeRunner _runner;

  bool get isRunning => _runner.isRunning;

  void start() => _runner.start();

  void stop() => _runner.stop();

  Future<void> purgeNow() => _runner.purgeNow();
}
