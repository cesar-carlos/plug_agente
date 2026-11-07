import 'package:plug_agente/domain/protocol/rpc_protocol_meta.dart';

/// Transport state. Wire budgets may only shorten its deadline, never authorize.
final class ActionIoRpcCallContext {
  const ActionIoRpcCallContext({
    required this.connectionId,
    required this.deadline,
    required this.isBatch,
    required this.isCancelled,
    this.onReadWait,
    this.receivedAt,
    this.receivedMonotonicMs,
    this.monotonicDeadlineMs,
    this.monotonicNow,
  });
  static const zoneKey = #actionIoRpcCallContext;
  final String connectionId;
  final DateTime deadline;
  final DateTime? receivedAt;
  final int? receivedMonotonicMs;
  final int? monotonicDeadlineMs;
  final int Function()? monotonicNow;
  Duration get remaining => monotonicDeadlineMs != null && monotonicNow != null
      ? Duration(milliseconds: monotonicDeadlineMs! - monotonicNow!())
      : deadline.difference(DateTime.now());
  bool get isActive => !isCancelled() && remaining > Duration.zero;

  /// The remote deadline is already expressed in this connection's local clock.
  /// Never renew it on arrival, decoding, queuing, or a cancellation wrapper.
  ActionIoRpcCallContext withMonotonicBudget({
    required String clockId,
    required int deadlineMs,
    required int remainingMs,
  }) {
    final now = monotonicNow;
    final received = receivedMonotonicMs;
    var bounded = 0;
    if (clockId == connectionId && now != null && received != null) {
      bounded = deadlineMs;
      final local = received + remainingMs.clamp(0, 30000);
      if (local < bounded) bounded = local;
      if (monotonicDeadlineMs != null && monotonicDeadlineMs! < bounded) bounded = monotonicDeadlineMs!;
    }
    return ActionIoRpcCallContext(
      connectionId: connectionId,
      deadline: deadline,
      receivedAt: receivedAt,
      receivedMonotonicMs: receivedMonotonicMs,
      monotonicDeadlineMs: bounded,
      monotonicNow: now ?? (() => 0),
      isBatch: isBatch,
      isCancelled: isCancelled,
      onReadWait: onReadWait,
    );
  }

  ActionIoRpcCallContext withRequestBudget(RpcProtocolMeta? meta, {required bool clockNegotiated}) {
    final remainingMs = meta?.actionIoRemainingMs;
    final deadlineUnixMs = meta?.actionIoDeadlineUnixMs;
    final clockId = meta?.actionIoClockId;
    final ticks = meta?.actionIoMonotonicDeadlineMs;
    if (clockNegotiated || clockId != null || ticks != null) {
      return withMonotonicBudget(
        clockId: clockNegotiated ? (clockId ?? '') : '',
        deadlineMs: ticks ?? 0,
        remainingMs: remainingMs ?? 0,
      );
    }
    return remainingMs != null && deadlineUnixMs != null
        ? withTransportBudget(remainingMs: remainingMs, deadlineUnixMs: deadlineUnixMs)
        : this;
  }

  final bool isBatch;
  final bool Function() isCancelled;

  /// Transfers an authorized waiting read out of the general dispatch capacity.
  final void Function()? onReadWait;

  ActionIoRpcCallContext withCancellation(bool Function() cancelled) => ActionIoRpcCallContext(
    connectionId: connectionId,
    deadline: deadline,
    receivedAt: receivedAt,
    receivedMonotonicMs: receivedMonotonicMs,
    monotonicDeadlineMs: monotonicDeadlineMs,
    monotonicNow: monotonicNow,
    isBatch: isBatch,
    isCancelled: () => isCancelled() || cancelled(),
    onReadWait: onReadWait,
  );

  ActionIoRpcCallContext withTransportBudget({required int remainingMs, required int deadlineUnixMs}) {
    final relative = (receivedAt ?? DateTime.now()).add(Duration(milliseconds: remainingMs));
    final absolute = DateTime.fromMillisecondsSinceEpoch(deadlineUnixMs, isUtc: true);
    var bounded = deadline;
    if (relative.isBefore(bounded)) bounded = relative;
    if (absolute.isBefore(bounded)) bounded = absolute;
    return ActionIoRpcCallContext(
      connectionId: connectionId,
      deadline: bounded,
      receivedAt: receivedAt,
      receivedMonotonicMs: receivedMonotonicMs,
      monotonicDeadlineMs: monotonicDeadlineMs,
      monotonicNow: monotonicNow,
      isBatch: isBatch,
      isCancelled: isCancelled,
      onReadWait: onReadWait,
    );
  }
}
