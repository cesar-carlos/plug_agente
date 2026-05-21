import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionCapturedOutputPurge = Future<Result<int>> Function({DateTime? now});

/// Best-effort periodic purge of stored stdout/stderr on old terminal executions.
class AgentActionCapturedOutputPeriodicPurge {
  AgentActionCapturedOutputPeriodicPurge(
    this._purge, {
    Duration interval = ConnectionConstants.agentActionCapturedOutputPurgeInterval,
  }) : _interval = interval;

  final AgentActionCapturedOutputPurge _purge;
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
              'Cleared captured output on $count agent action execution row(s) (periodic)',
              name: 'agent_action_captured_output_periodic_purge',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Periodic agent action captured output purge failed (continuing)',
            name: 'agent_action_captured_output_periodic_purge',
            level: 900,
            error: failure,
          );
        },
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Periodic agent action captured output purge failed (continuing)',
        name: 'agent_action_captured_output_periodic_purge',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
