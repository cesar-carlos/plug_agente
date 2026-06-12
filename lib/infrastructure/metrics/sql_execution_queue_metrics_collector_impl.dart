import 'dart:developer' as developer;

import 'package:plug_agente/domain/repositories/sql_execution_queue_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

final class SqlExecutionQueueMetricsCollectorImpl implements SqlExecutionQueueMetricsCollector {
  SqlExecutionQueueMetricsCollectorImpl(this._store);

  final MetricsEventStore _store;

  int get rejectionCount => _store.counterValue(MetricsCounterNames.sqlQueueRejectionCounter);
  int get timeoutCount => _store.counterValue(MetricsCounterNames.sqlQueueTimeoutCounter);
  int get timeoutAfterWorkerStartedCount =>
      _store.counterValue(MetricsCounterNames.sqlQueueTimeoutAfterWorkerStartedCounter);
  int get saturation70Count => _store.counterValue(MetricsCounterNames.sqlQueueSaturation70Counter);
  int get saturation90Count => _store.counterValue(MetricsCounterNames.sqlQueueSaturation90Counter);
  int get workersEqualPoolCount => _store.counterValue(MetricsCounterNames.sqlQueueWorkersEqualPoolCounter);

  @override
  void recordQueueAdded(int currentSize) => recordQueueSizeChanged(currentSize);

  @override
  void recordQueueSizeChanged(int currentSize) {
    _store.currentQueueSize = currentSize;
    if (currentSize > _store.maxQueueSize) {
      _store.maxQueueSize = currentSize;
    }
  }

  @override
  void recordQueueRejection() {
    _store.incrementEventCounter(MetricsCounterNames.sqlQueueRejectionCounter);
  }

  @override
  void recordQueueTimeout() {
    _store.incrementEventCounter(MetricsCounterNames.sqlQueueTimeoutCounter);
  }

  @override
  void recordQueueTimeoutAfterWorkerStarted() {
    _store.incrementEventCounter(MetricsCounterNames.sqlQueueTimeoutAfterWorkerStartedCounter);
    final count = timeoutAfterWorkerStartedCount;
    _store.recordDiagnosticReason(category: 'sql_queue', reason: 'ghost_query_risk');
    if (count == 1 || count % 5 == 0) {
      developer.log(
        'SQL queue timeout after worker started — ghost query risk (in-flight ODBC may continue)',
        name: 'metrics',
        level: 900,
        error: {
          'ghost_query_risk': true,
          'sql_queue_timeout_after_worker_started_count': count,
        },
      );
    }
  }

  @override
  void recordQueueSaturation({
    required int thresholdPercent,
    required int currentSize,
    required int maxSize,
  }) {
    final counter = switch (thresholdPercent) {
      70 => MetricsCounterNames.sqlQueueSaturation70Counter,
      90 => MetricsCounterNames.sqlQueueSaturation90Counter,
      _ => 'sql_queue_saturation_$thresholdPercent',
    };
    _store.incrementEventCounter(counter);
    developer.log(
      'SQL queue saturation crossed $thresholdPercent%',
      name: 'metrics',
      level: 900,
      error: {
        'current_size': currentSize,
        'max_size': maxSize,
        'threshold_percent': thresholdPercent,
      },
    );
  }

  @override
  void recordQueueWaitTime(Duration waitTime) {
    _store.recordDurationSample(_store.queueWaitTimes, waitTime);
  }

  @override
  void recordWorkerStarted(int activeCount) {
    _store.currentActiveWorkers = activeCount;
    if (activeCount > _store.maxActiveWorkers) {
      _store.maxActiveWorkers = activeCount;
    }
  }

  @override
  void recordWorkerCompleted(int activeCount) {
    _store.currentActiveWorkers = activeCount;
  }

  @override
  void recordStreamingWorkerHoldTime(Duration holdTime) {
    if (holdTime.isNegative) {
      return;
    }
    _store.recordDurationSample(_store.streamingWorkerHoldTimes, holdTime);
  }

  void recordSqlQueueWorkersEqualPool({
    required int workers,
    required int poolSize,
  }) {
    _store.incrementEventCounter(MetricsCounterNames.sqlQueueWorkersEqualPoolCounter);
    developer.log(
      'SQL queue workers match ODBC pool size',
      name: 'metrics',
      level: 800,
      error: {
        'workers': workers,
        'pool_size': poolSize,
      },
    );
  }
}
