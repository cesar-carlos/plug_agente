/// Metrics for action execution queue; stable counter keys for snapshots/OTel.
abstract class ActionExecutionQueueMetricsCollector {
  void recordConcurrencyReject();

  void recordConcurrencyIgnore();

  void recordQueueDepthFull();

  void recordPendingEnqueued();

  void recordIdempotentReplay();

  void recordRunStarted();

  void recordPendingWaitTimeout();

  void recordPendingCancelled();

  void recordPendingDequeueWaitTime(Duration wait);
}
