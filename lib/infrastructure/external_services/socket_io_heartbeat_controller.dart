import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';

/// Owns Socket.IO hub heartbeat timers and missed-ack counting.
///
/// The transport client supplies [emitHeartbeat] (emit `agent:heartbeat`) and
/// logging / stale callbacks; this type stays free of Socket.IO types.
final class SocketIoHeartbeatController {
  SocketIoHeartbeatController({
    required this.isConnected,
    required this.emitHeartbeat,
    required this.logMessage,
    required this.onConnectionStale,
    Duration? interval,
    Duration? ackTimeout,
    int? maxMissed,
  }) : _interval = interval ?? ConnectionConstants.socketHeartbeatInterval,
       _ackTimeout = ackTimeout ?? ConnectionConstants.socketHeartbeatAckTimeout,
       _maxMissed = maxMissed ?? ConnectionConstants.socketMaxMissedHeartbeats {
    // ackTimeout must be strictly less than the periodic interval. If it were
    // equal or greater, a late ack-timer fire and the next periodic tick could
    // both call _handleTimeout for the same beat, doubling _missedHeartbeats.
    assert(
      _ackTimeout < _interval,
      'socketHeartbeatAckTimeout ($_ackTimeout) must be less than '
      'socketHeartbeatInterval ($_interval)',
    );
  }

  final bool Function() isConnected;
  final Future<bool> Function() emitHeartbeat;
  final void Function(String direction, String event, dynamic data) logMessage;
  final void Function() onConnectionStale;

  final Duration _interval;
  final Duration _ackTimeout;
  final int _maxMissed;

  Timer? _periodicTimer;
  Timer? _ackTimer;
  bool _waitingAck = false;
  int _missedHeartbeats = 0;

  void resetTransientState() {
    _missedHeartbeats = 0;
    _waitingAck = false;
    _ackTimer?.cancel();
    _ackTimer = null;
  }

  void start() {
    stop();
    _missedHeartbeats = 0;
    _periodicTimer = Timer.periodic(_interval, (_) => _onPeriodicTick());
    _onPeriodicTick();
  }

  void stop() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    _waitingAck = false;
  }

  void onAckReceived() {
    _ackTimer?.cancel();
    _waitingAck = false;
    _missedHeartbeats = 0;
  }

  void _onPeriodicTick() {
    if (!isConnected()) {
      return;
    }
    // If we are still waiting for an ack from the previous beat, the _ackTimer
    // has already fired (or is about to) and will increment _missedHeartbeats.
    // Do not emit another heartbeat until the pending one is resolved.
    if (_waitingAck) {
      return;
    }

    unawaited(_emitAndArmAck());
  }

  Future<void> _emitAndArmAck() async {
    final emitted = await emitHeartbeat();
    if (!emitted) {
      logMessage('ERROR', 'heartbeat_emit_failed', {
        'missed_heartbeats': _missedHeartbeats,
      });
      return;
    }
    if (!isConnected()) {
      return;
    }
    _waitingAck = true;
    _ackTimer?.cancel();
    _ackTimer = Timer(_ackTimeout, _handleTimeout);
  }

  void _handleTimeout() {
    _ackTimer?.cancel();
    _waitingAck = false;
    _missedHeartbeats++;

    logMessage('ERROR', 'heartbeat_timeout', {
      'missed_heartbeats': _missedHeartbeats,
    });

    if (_missedHeartbeats < _maxMissed) {
      return;
    }

    logMessage('ERROR', 'connection_stale', {
      'reason': RpcStreamingConstants.missedHeartbeatAckReason,
      'missed_heartbeats': _missedHeartbeats,
    });
    stop();
    onConnectionStale();
  }
}
