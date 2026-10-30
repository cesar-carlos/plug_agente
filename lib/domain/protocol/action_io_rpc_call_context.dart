/// Transport state. Wire budgets may only shorten its deadline, never authorize.
final class ActionIoRpcCallContext {
  const ActionIoRpcCallContext({
    required this.connectionId,
    required this.deadline,
    required this.isBatch,
    required this.isCancelled,
    this.onReadWait,
    this.receivedAt,
  });
  static const zoneKey = #actionIoRpcCallContext;
  final String connectionId;
  final DateTime deadline;
  final DateTime? receivedAt;
  final bool isBatch;
  final bool Function() isCancelled;

  /// Transfers an authorized waiting read out of the general dispatch capacity.
  final void Function()? onReadWait;

  ActionIoRpcCallContext withCancellation(bool Function() cancelled) => ActionIoRpcCallContext(
    connectionId: connectionId,
    deadline: deadline,
    receivedAt: receivedAt,
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
      isBatch: isBatch,
      isCancelled: isCancelled,
      onReadWait: onReadWait,
    );
  }
}
