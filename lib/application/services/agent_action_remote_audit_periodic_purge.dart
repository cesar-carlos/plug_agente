import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionRemoteAuditExpiredPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Best-effort periodic purge of append-only remote audit rows past retention.
class AgentActionRemoteAuditPeriodicPurge {
  AgentActionRemoteAuditPeriodicPurge(
    AgentActionRemoteAuditExpiredPurge purge, {
    Duration interval = ConnectionConstants.agentActionRemoteAuditPurgeInterval,
  }) : _runner = PeriodicPurgeRunner(
          purge: () => purge(),
          interval: interval,
          logName: 'agent_action_remote_audit_periodic_purge',
          successLogMessage: (int count) =>
              'Purged $count old agent action remote audit row(s) (periodic)',
          failureLogMessage: 'Periodic agent action remote audit purge failed (continuing)',
        );

  final PeriodicPurgeRunner _runner;

  bool get isRunning => _runner.isRunning;

  void start() => _runner.start();

  void stop() => _runner.stop();

  Future<void> purgeNow() => _runner.purgeNow();
}
