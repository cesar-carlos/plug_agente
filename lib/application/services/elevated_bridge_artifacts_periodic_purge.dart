import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef ElevatedBridgeArtifactsExpiredPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Best-effort periodic purge of stale elevated bridge artifact files.
class ElevatedBridgeArtifactsPeriodicPurge {
  ElevatedBridgeArtifactsPeriodicPurge(
    this._purge, {
    Duration interval = AgentActionElevatedConstants.bridgeArtifactPurgeInterval,
  }) : _interval = interval;

  final ElevatedBridgeArtifactsExpiredPurge _purge;
  final Duration _interval;
  Timer? _timer;

  bool get isRunning => _timer != null;

  void start() {
    if (_timer != null) {
      return;
    }
    _timer = Timer.periodic(_interval, (_) {
      unawaited(purgeNow());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> purgeNow() async {
    try {
      final result = await _purge();
      result.fold(
        (int count) {
          if (count > 0) {
            developer.log(
              'Purged $count stale elevated bridge artifact file(s) (periodic)',
              name: 'elevated_bridge_artifacts_periodic_purge',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Periodic elevated bridge artifact purge failed (continuing)',
            name: 'elevated_bridge_artifacts_periodic_purge',
            level: 900,
            error: failure,
          );
        },
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Periodic elevated bridge artifact purge failed (continuing)',
        name: 'elevated_bridge_artifacts_periodic_purge',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
