/// Result of (optionally) starting a batch transaction: carries the engine
/// transaction id, or null when the batch is non-transactional.
class BatchTransactionStart {
  const BatchTransactionStart(this.transactionId);

  final int? transactionId;
}

/// Tracks the lifecycle of a batch transaction so it is rolled back at most
/// once and never after a successful commit.
class BatchTransactionGuard {
  BatchTransactionGuard(this.transactionId);

  final int? transactionId;
  bool _closed = false;

  bool get isActive => transactionId != null && !_closed;

  /// Invokes [rollback] for the active transaction id exactly once, marking the
  /// guard closed. No-op when there is no transaction or it is already closed.
  Future<void> rollback(
    Future<void> Function(int transactionId) rollback,
  ) async {
    final id = transactionId;
    if (id == null || _closed) {
      return;
    }

    _closed = true;
    await rollback(id);
  }

  void markCommitted() {
    _closed = true;
  }
}
