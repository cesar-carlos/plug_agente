import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';

/// Coalesces inbound `rpc:request_ack` emissions into batched `rpc:batch_ack`.
class RpcInboundAckCoalescer {
  RpcInboundAckCoalescer({
    required Future<void> Function(String event, dynamic payload) emitEvent,
  }) : _emitEvent = emitEvent;

  final Future<void> Function(String event, dynamic payload) _emitEvent;

  final List<String> _pendingAckIds = <String>[];
  Timer? _ackFlushTimer;

  /// Buffers an inbound `rpc:request` ack and flushes either when the buffer
  /// reaches [ConnectionConstants.rpcAckCoalesceMaxBatch] or after
  /// [ConnectionConstants.rpcAckCoalesceFlushInterval] elapses, whichever
  /// happens first. A buffer of size 1 still emits the canonical
  /// `rpc:request_ack`, preserving the legacy single-id wire shape.
  void scheduleAck(dynamic requestId) {
    if (requestId == null) return;
    _pendingAckIds.add(requestId.toString());
    if (_pendingAckIds.length >= ConnectionConstants.rpcAckCoalesceMaxBatch) {
      _ackFlushTimer?.cancel();
      _ackFlushTimer = null;
      unawaited(_flushPendingAcks());
      return;
    }
    _ackFlushTimer ??= Timer(ConnectionConstants.rpcAckCoalesceFlushInterval, () {
      _ackFlushTimer = null;
      unawaited(_flushPendingAcks());
    });
  }

  /// Cancels the ack-flush timer and discards any pending acks.
  void resetAckBuffer() {
    _ackFlushTimer?.cancel();
    _ackFlushTimer = null;
    _pendingAckIds.clear();
  }

  Future<void> _flushPendingAcks() async {
    if (_pendingAckIds.isEmpty) return;
    final ids = List<String>.unmodifiable(_pendingAckIds);
    _pendingAckIds.clear();
    final receivedAt = DateTime.now().toIso8601String();
    if (ids.length == 1) {
      await _emitEvent('rpc:request_ack', <String, dynamic>{
        'request_id': ids.first,
        'received_at': receivedAt,
      });
      return;
    }
    await _emitEvent('rpc:batch_ack', <String, dynamic>{
      'request_ids': ids,
      'received_at': receivedAt,
    });
  }
}
