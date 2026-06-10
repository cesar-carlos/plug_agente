/// Metrics collector interface for SQL execution queue.
abstract class SqlExecutionQueueMetricsCollector {
  void recordQueueAdded(int currentSize);
  void recordQueueSizeChanged(int currentSize);
  void recordQueueRejection();
  void recordQueueTimeout();
  void recordQueueTimeoutAfterWorkerStarted();
  void recordQueueSaturation({
    required int thresholdPercent,
    required int currentSize,
    required int maxSize,
  });
  void recordQueueWaitTime(Duration waitTime);
  void recordWorkerStarted(int activeCount);
  void recordWorkerCompleted(int activeCount);
  void recordStreamingWorkerHoldTime(Duration holdTime);
}
