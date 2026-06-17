import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';

final class SqlExecutionQueueSaturationTracker {
  bool reportedSaturation70 = false;
  bool reportedSaturation90 = false;

  void recordIfNeeded({
    required int queuedCount,
    required int maxQueueSize,
    SqlExecutionQueueMetricsCollector? metricsCollector,
  }) {
    final saturationPercent = queuedCount / maxQueueSize * 100;
    reportedSaturation70 = _recordThresholdCrossing(
      isActive: reportedSaturation70,
      saturationPercent: saturationPercent,
      thresholdPercent: 70,
      queuedCount: queuedCount,
      maxQueueSize: maxQueueSize,
      metricsCollector: metricsCollector,
    );
    reportedSaturation90 = _recordThresholdCrossing(
      isActive: reportedSaturation90,
      saturationPercent: saturationPercent,
      thresholdPercent: 90,
      queuedCount: queuedCount,
      maxQueueSize: maxQueueSize,
      metricsCollector: metricsCollector,
    );
  }

  bool _recordThresholdCrossing({
    required bool isActive,
    required double saturationPercent,
    required int thresholdPercent,
    required int queuedCount,
    required int maxQueueSize,
    SqlExecutionQueueMetricsCollector? metricsCollector,
  }) {
    if (saturationPercent < thresholdPercent) {
      return false;
    }
    if (isActive) {
      return true;
    }
    metricsCollector?.recordQueueSaturation(
      thresholdPercent: thresholdPercent,
      currentSize: queuedCount,
      maxSize: maxQueueSize,
    );
    return true;
  }
}
