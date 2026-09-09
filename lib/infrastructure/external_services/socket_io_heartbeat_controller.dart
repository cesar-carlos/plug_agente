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
    this.emitHeartbeatWithEpoch,
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
  final Future<bool> Function(int heartbeatEpoch)? emitHeartbeatWithEpoch;
  final void Function(String direction, String event, dynamic data) logMessage;
  final void Function() onConnectionStale;

  final Duration _interval;
  final Duration _ackTimeout;
  final int _maxMissed;

  Timer? _periodicTimer;
  Timer? _ackTimer;
  bool _waitingAck = false;
  int _missedHeartbeats = 0;
  int _heartbeatEpoch = 0;
  String? _expectedTraceId;

  void resetTransientState() {
    _heartbeatEpoch++;
    _missedHeartbeats = 0;
    _waitingAck = false;
    _expectedTraceId = null;
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
    _heartbeatEpoch++;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _ackTimer?.cancel();
    _ackTimer = null;
    _waitingAck = false;
    _expectedTraceId = null;
  }

  bool registerExpectedTraceId(String traceId, int heartbeatEpoch) {
    if (heartbeatEpoch != _heartbeatEpoch) {
      return false;
    }
    _expectedTraceId = traceId;
    return true;
  }

  bool onAckReceived([String? traceId]) {
    if (ackRejectionReason(traceId) != null) {
      return false;
    }
    _ackTimer?.cancel();
    _waitingAck = false;
    _missedHeartbeats = 0;
    _expectedTraceId = null;
    return true;
  }

  String? ackRejectionReason([String? traceId]) {
    if (!_waitingAck) {
      return 'not_waiting';
    }
    if (_expectedTraceId == null) {
      return null;
    }
    if (traceId == null || traceId.isEmpty) {
      return 'trace_missing';
    }
    if (traceId != _expectedTraceId) {
      return 'trace_mismatch';
    }
    return null;
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

    unawaited(_emitAndArmAck(_heartbeatEpoch));
  }

  Future<void> _emitAndArmAck(int heartbeatEpoch) async {
    final emitted = await (emitHeartbeatWithEpoch?.call(heartbeatEpoch) ?? emitHeartbeat());
    if (heartbeatEpoch != _heartbeatEpoch) {
      return;
    }
    if (!emitted) {
      _expectedTraceId = null;
      logMessage('ERROR', 'heartbeat_emit_failed', {
        'missed_heartbeats': _missedHeartbeats,
      });
      return;
    }
    if (!isConnected()) {
      _expectedTraceId = null;
      return;
    }
    _waitingAck = true;
    _ackTimer?.cancel();
    _ackTimer = Timer(_ackTimeout, () {
      if (heartbeatEpoch == _heartbeatEpoch) {
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    _ackTimer?.cancel();
    _waitingAck = false;
    _expectedTraceId = null;
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
