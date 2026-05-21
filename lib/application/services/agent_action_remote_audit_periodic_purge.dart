import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionRemoteAuditExpiredPurge = Future<Result<int>> Function({DateTime? referenceTime});

/// Best-effort periodic purge of append-only remote audit rows past retention.
class AgentActionRemoteAuditPeriodicPurge {
  AgentActionRemoteAuditPeriodicPurge(
    this._purge, {
    Duration interval = ConnectionConstants.agentActionRemoteAuditPurgeInterval,
  }) : _interval = interval;

  final AgentActionRemoteAuditExpiredPurge _purge;
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
              'Purged $count old agent action remote audit row(s) (periodic)',
              name: 'agent_action_remote_audit_periodic_purge',
              level: 800,
            );
          }
        },
        (Object failure) {
          developer.log(
            'Periodic agent action remote audit purge failed (continuing)',
            name: 'agent_action_remote_audit_periodic_purge',
            level: 900,
            error: failure,
          );
        },
      );
    } on Object catch (error, stackTrace) {
      developer.log(
        'Periodic agent action remote audit purge failed (continuing)',
        name: 'agent_action_remote_audit_periodic_purge',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
