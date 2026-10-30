/// Fixed-cardinality outcomes; never include caller identity or native text.
enum ActionIoRemoteOutcome { success, unauthorized, limited, cancelled, unknown, failed }

enum ActionIoInputOutcome { written, failed, unknown }

enum ActionIoExecutionOutcome { succeeded, failed, cancelled, unknown }

abstract interface class IActionIoMetrics {
  void recordRemoteOutcome(ActionIoRemoteOutcome outcome);
  void setActiveReaders(int count);
  void setQueueWaiting(int count);

  /// Counts delivered pages, including deliberate cursor rereads, not storage.
  void recordReadBytes(int count);

  /// Counts new output bytes only after their journal transaction commits.
  void recordPersistedOutputBytes(int count);

  /// Counts unique admitted stdin bytes after commit, including initial input.
  void recordAdmittedInputBytes(int count);

  /// Counts sessions newly reconciled to unknown, not previously unknown rows.
  void recordInterruptedExecutions(int count);

  /// Records a newly committed delivery outcome, never a duplicate receipt.
  /// Null progress remains unknown and must not be represented as zero.
  void recordInputOutcome(ActionIoInputOutcome outcome, {required int? confirmedBytes});

  /// Records committed execution and capture states independently.
  void recordExecutionOutcome(ActionIoExecutionOutcome outcome, {required bool captureComplete});

  /// Ownership includes preparation/draining, not only live operating-system processes.
  void setLifecycle({required int launches, required int sessions, required bool cleanupUnconfirmed});
}
