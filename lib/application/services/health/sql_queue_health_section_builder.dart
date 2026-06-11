import 'package:plug_agente/application/gateway/queued_database_gateway.dart';

final class SqlQueueHealthSectionBuilder {
  const SqlQueueHealthSectionBuilder();

  Map<String, Object?> build({
    required QueuedDatabaseGateway? queuedGateway,
    required Map<String, Object?> metrics,
  }) {
    if (queuedGateway == null) {
      return const {'enabled': false};
    }

    return {
      'enabled': true,
      'current_size': queuedGateway.queueSize,
      'max_size': queuedGateway.maxQueueSize,
      'active_workers': queuedGateway.activeWorkers,
      'max_workers': queuedGateway.maxWorkers,
      'active_batch_workers': queuedGateway.activeBatchWorkers,
      'max_batch_workers': queuedGateway.maxBatchWorkers,
      'active_long_query_workers': queuedGateway.activeLongQueryWorkers,
      'max_long_query_workers': queuedGateway.maxLongQueryWorkers,
      'active_streaming_workers': queuedGateway.activeStreamingWorkers,
      'max_streaming_workers': queuedGateway.maxStreamingWorkers,
      'active_non_query_workers': queuedGateway.activeNonQueryWorkers,
      'max_non_query_workers': queuedGateway.maxNonQueryWorkers,
      'enqueue_timeout_seconds': queuedGateway.enqueueTimeout.inSeconds,
      'rejections_total': metrics['sql_queue_rejection_count'] ?? 0,
      'timeouts_total': metrics['sql_queue_timeout_count'] ?? 0,
      'timeouts_after_worker_started_total': metrics['sql_queue_timeout_after_worker_started_count'] ?? 0,
      'avg_wait_time_ms': (metrics['sql_queue_avg_wait_time_ms'] as num?)?.toInt() ?? 0,
      'p95_wait_time_ms': (metrics['sql_queue_p95_wait_time_ms'] as num?)?.toInt() ?? 0,
      'max_recent_wait_time_ms': (metrics['sql_queue_max_recent_wait_time_ms'] as num?)?.toInt() ?? 0,
      'pool_wait_avg_time_ms': (metrics['pool_wait_avg_time_ms'] as num?)?.toInt() ?? 0,
      'pool_wait_p95_time_ms': (metrics['pool_wait_p95_time_ms'] as num?)?.toInt() ?? 0,
      'connect_avg_time_ms': (metrics['connect_avg_time_ms'] as num?)?.toInt() ?? 0,
      'sql_execution_avg_time_ms': (metrics['sql_execution_avg_time_ms'] as num?)?.toInt() ?? 0,
      'saturation_70_total': metrics['sql_queue_saturation_70_count'] ?? 0,
      'saturation_90_total': metrics['sql_queue_saturation_90_count'] ?? 0,
      'workers_equal_pool_total': metrics['sql_queue_workers_equal_pool_count'] ?? 0,
      'pool_wait_timeouts_total': metrics['pool_acquire_timeout_count'] ?? 0,
      'streaming_worker_hold_avg_ms': (metrics['streaming_worker_hold_avg_time_ms'] as num?)?.toInt() ?? 0,
      'streaming_worker_hold_p95_ms': (metrics['streaming_worker_hold_p95_time_ms'] as num?)?.toInt() ?? 0,
      'streaming_worker_hold_max_recent_ms':
          (metrics['streaming_worker_hold_max_recent_time_ms'] as num?)?.toInt() ?? 0,
      'streaming_worker_hold_sample_count': metrics['streaming_worker_hold_sample_count'] ?? 0,
    };
  }
}
