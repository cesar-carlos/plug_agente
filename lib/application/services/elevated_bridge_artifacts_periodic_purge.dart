import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef ElevatedBridgeArtifactsExpiredPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Best-effort periodic purge of stale elevated bridge artifact files.
class ElevatedBridgeArtifactsPeriodicPurge {
  ElevatedBridgeArtifactsPeriodicPurge(
    ElevatedBridgeArtifactsExpiredPurge purge, {
    Duration interval = AgentActionElevatedConstants.bridgeArtifactPurgeInterval,
  }) : _runner = PeriodicPurgeRunner(
         purge: () => purge(),
         interval: interval,
         logName: 'elevated_bridge_artifacts_periodic_purge',
         successLogMessage: (int count) => 'Purged $count stale elevated bridge artifact file(s) (periodic)',
         failureLogMessage: 'Periodic elevated bridge artifact purge failed (continuing)',
       );

  final PeriodicPurgeRunner _runner;

  bool get isRunning => _runner.isRunning;

  void start() => _runner.start();

  void stop() => _runner.stop();

  Future<void> purgeNow() => _runner.purgeNow();
}
