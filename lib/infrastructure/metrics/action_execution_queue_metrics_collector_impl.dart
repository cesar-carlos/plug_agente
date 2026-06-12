import 'package:plug_agente/domain/repositories/action_execution_queue_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

final class ActionExecutionQueueMetricsCollectorImpl implements ActionExecutionQueueMetricsCollector {
  ActionExecutionQueueMetricsCollectorImpl(this._store);

  final MetricsEventStore _store;

  @override
  void recordConcurrencyReject() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueueConcurrencyRejectCounter);
  }

  @override
  void recordConcurrencyIgnore() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueueConcurrencyIgnoreCounter);
  }

  @override
  void recordQueueDepthFull() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueueDepthFullCounter);
  }

  @override
  void recordPendingEnqueued() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueuePendingEnqueuedCounter);
  }

  @override
  void recordIdempotentReplay() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueueIdempotentReplayCounter);
  }

  @override
  void recordRunStarted() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueueRunStartedCounter);
  }

  @override
  void recordPendingWaitTimeout() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueuePendingWaitTimeoutCounter);
  }

  @override
  void recordPendingCancelled() {
    _store.incrementEventCounter(MetricsCounterNames.agentActionQueuePendingCancelledCounter);
  }

  @override
  void recordPendingDequeueWaitTime(Duration wait) {
    _store.recordDurationSample(_store.agentActionQueueWaitTimes, wait);
  }
}
