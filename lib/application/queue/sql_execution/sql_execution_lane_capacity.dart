import 'package:plug_agente/application/queue/sql_execution/sql_execution_queued_request.dart';
import 'package:plug_agente/application/queue/sql_execution_kind.dart';
import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';

final class SqlExecutionLaneCapacity {
  SqlExecutionLaneCapacity({
    required this.maxConcurrentWorkers,
    required this.maxConcurrentBatchWorkers,
    required this.maxConcurrentLongQueryWorkers,
    required this.maxConcurrentStreamingWorkers,
    required this.maxConcurrentNonQueryWorkers,
  });

  final int maxConcurrentWorkers;
  final int maxConcurrentBatchWorkers;
  final int maxConcurrentLongQueryWorkers;
  final int maxConcurrentStreamingWorkers;
  final int maxConcurrentNonQueryWorkers;

  int activeWorkers = 0;
  int activeBatchWorkers = 0;
  int activeLongQueryWorkers = 0;
  int activeStreamingWorkers = 0;
  int activeNonQueryWorkers = 0;

  bool hasAvailableWorkerSlot() => activeWorkers < maxConcurrentWorkers;

  bool canStart(SqlExecutionQueuedRequest<Object> request) {
    return switch (request.kind) {
      SqlExecutionKind.batch => activeBatchWorkers + request.slotWeight <= maxConcurrentBatchWorkers,
      SqlExecutionKind.longQuery => activeLongQueryWorkers < maxConcurrentLongQueryWorkers,
      SqlExecutionKind.streaming => activeStreamingWorkers < maxConcurrentStreamingWorkers,
      SqlExecutionKind.nonQuery => activeNonQueryWorkers < maxConcurrentNonQueryWorkers,
      SqlExecutionKind.shortQuery || SqlExecutionKind.query => true,
    };
  }

  void onWorkerStarted(
    SqlExecutionQueuedRequest<Object> request, {
    SqlExecutionQueueMetricsCollector? metricsCollector,
  }) {
    activeWorkers++;
    if (request.kind == SqlExecutionKind.batch) {
      activeBatchWorkers += request.slotWeight;
    }
    if (request.kind == SqlExecutionKind.longQuery) {
      activeLongQueryWorkers++;
    }
    if (request.kind == SqlExecutionKind.streaming) {
      activeStreamingWorkers++;
    }
    if (request.kind == SqlExecutionKind.nonQuery) {
      activeNonQueryWorkers++;
    }
    metricsCollector?.recordWorkerStarted(activeWorkers);
  }

  void onWorkerReleased(
    SqlExecutionQueuedRequest<Object> request, {
    SqlExecutionQueueMetricsCollector? metricsCollector,
  }) {
    if (request.kind == SqlExecutionKind.streaming) {
      final startedAt = request.startedAt;
      if (startedAt != null) {
        metricsCollector?.recordStreamingWorkerHoldTime(
          DateTime.now().difference(startedAt),
        );
      }
    }
    activeWorkers--;
    if (request.kind == SqlExecutionKind.batch && activeBatchWorkers > 0) {
      activeBatchWorkers = (activeBatchWorkers - request.slotWeight).clamp(0, maxConcurrentBatchWorkers);
    }
    if (request.kind == SqlExecutionKind.longQuery && activeLongQueryWorkers > 0) {
      activeLongQueryWorkers--;
    }
    if (request.kind == SqlExecutionKind.streaming && activeStreamingWorkers > 0) {
      activeStreamingWorkers--;
    }
    if (request.kind == SqlExecutionKind.nonQuery && activeNonQueryWorkers > 0) {
      activeNonQueryWorkers--;
    }
    metricsCollector?.recordWorkerCompleted(activeWorkers);
  }
}
