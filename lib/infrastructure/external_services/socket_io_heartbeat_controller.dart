import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';

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
       _maxMissed = maxMissed ?? ConnectionConstants.socketMaxMissedHeartbeats;

  final bool Function() isConnected;
  final void Function() emitHeartbeat;
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

    if (_waitingAck) {
      return;
    }

    _waitingAck = true;
    emitHeartbeat();

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
      'reason': 'missed_heartbeat_ack',
      'missed_heartbeats': _missedHeartbeats,
    });
    stop();
    onConnectionStale();
  }
}
