import 'dart:collection';

import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

/// Builds health/monitoring snapshots from query metrics and the event store.
final class MetricsCollectorSnapshotBuilder {
  const MetricsCollectorSnapshotBuilder._();

  static Map<String, Object> build({
    required Iterable<QueryMetrics> queryMetrics,
    required MetricsEventStore store,
    required Duration? p95QueueWaitTime,
    required Duration? maxRecentQueueWaitTime,
    required int sqlQueueRejectionCount,
    required int sqlQueueTimeoutCount,
    required int sqlQueueTimeoutAfterWorkerStartedCount,
    required int sqlQueueSaturation70Count,
    required int sqlQueueSaturation90Count,
    required int sqlQueueWorkersEqualPoolCount,
  }) {
    final metrics = queryMetrics.isNotEmpty ? queryMetrics : <QueryMetrics>[];
    final totalQueries = metrics.length;
    final successfulQueries = metrics.where((m) => m.success).length;
    final errorQueries = totalQueries - successfulQueries;

    final latencies = metrics.map((m) => m.executionDuration.inMilliseconds).toList()..sort();

    final avgLatency = latencies.isNotEmpty ? latencies.reduce((a, b) => a + b) / latencies.length : 0.0;

    final p95Latency = latencies.isNotEmpty ? latencies[(latencies.length * 0.95).floor()] : 0;

    final p99Latency = latencies.isNotEmpty ? latencies[(latencies.length * 0.99).floor()] : 0;

    return {
      'query_count': totalQueries,
      'query_error_count': errorQueries,
      'query_avg_latency_ms': avgLatency,
      'query_p95_latency_ms': p95Latency,
      'query_p99_latency_ms': p99Latency,
      'sql_queue_rejection_count': sqlQueueRejectionCount,
      'sql_queue_timeout_count': sqlQueueTimeoutCount,
      'sql_queue_timeout_after_worker_started_count': sqlQueueTimeoutAfterWorkerStartedCount,
      'sql_queue_saturation_70_count': sqlQueueSaturation70Count,
      'sql_queue_saturation_90_count': sqlQueueSaturation90Count,
      'sql_queue_workers_equal_pool_count': sqlQueueWorkersEqualPoolCount,
      'pool_acquire_timeout_count': store.counterValue(MetricsCounterNames.poolAcquireTimeoutCounter),
      'direct_connection_active_count': store.activeDirectConnections,
      'direct_connection_max_active_count': store.maxActiveDirectConnections,
      'direct_connection_opened': store.eventCounters['direct_connection_opened'] ?? 0,
      'direct_connection_closed': store.eventCounters['direct_connection_closed'] ?? 0,
      'sql_queue_current_size': store.currentQueueSize,
      'sql_queue_max_size': store.maxQueueSize,
      'sql_queue_current_workers': store.currentActiveWorkers,
      'sql_queue_max_workers': store.maxActiveWorkers,
      'sql_queue_avg_wait_time_ms': store.queueWaitTimes.isEmpty
          ? 0.0
          : store.queueWaitTimes.fold<int>(0, (sum, d) => sum + d.inMilliseconds) / store.queueWaitTimes.length,
      'sql_queue_p95_wait_time_ms': p95QueueWaitTime?.inMilliseconds ?? 0,
      'sql_queue_max_recent_wait_time_ms': maxRecentQueueWaitTime?.inMilliseconds ?? 0,
      ..._durationStatsSnapshot('agent_action_queue_wait', store.agentActionQueueWaitTimes),
      ..._durationStatsSnapshot('agent_action_execution', store.agentActionExecutionDurations),
      ..._durationStatsSnapshot('pool_wait', store.poolWaitTimes),
      ..._durationStatsSnapshot('direct_connection_wait', store.directConnectionWaitTimes),
      ..._durationStatsSnapshot('read_only_batch_parallel_wait', store.readOnlyBatchParallelWaitTimes),
      ..._durationStatsSnapshot('streaming_worker_hold', store.streamingWorkerHoldTimes),
      ..._durationStatsSnapshot('connect', store.connectTimes),
      ..._durationStatsSnapshot('sql_execution', store.sqlExecutionTimes),
      ..._durationStatsSnapshot('auto_update_probe', store.autoUpdateProbeTimes),
      ..._durationStatsSnapshot('auto_update_download', store.autoUpdateDownloadTimes),
      ..._sqlExecutionModeStatsSnapshot(store),
      'sql_execution_by_mode': _sqlExecutionModeNestedStatsSnapshot(store),
      ..._durationStatsSnapshot('prepared_prepare', store.preparedPrepareTimes),
      'rpc_sql_execute_db_streaming_skip_reasons': Map<String, int>.unmodifiable(store.streamingSkipReasons),
      'odbc_native_fallback_reasons': Map<String, int>.unmodifiable(store.odbcNativeFallbackReasons),
      'odbc_query_timeout_by_stage': Map<String, int>.unmodifiable(store.odbcQueryTimeoutByStage),
      'schema_validation_duration_us': store.schemaValidationDurationUs,
      'schema_validation_duration_by_schema_us': Map<String, int>.unmodifiable(store.schemaValidationDurationUsByKey),
      'schema_validation_count_by_schema': Map<String, int>.unmodifiable(store.schemaValidationCountByKey),
      'schema_validation_failure_by_schema': Map<String, int>.unmodifiable(store.schemaValidationFailuresByKey),
      'read_only_batch_parallel_last_requested': store.readOnlyBatchParallelLastRequested,
      'read_only_batch_parallel_last_effective': store.readOnlyBatchParallelLastEffective,
      'recent_diagnostic_reasons': List<String>.unmodifiable(store.recentDiagnosticReasons),
      'top_recent_diagnostic_reasons': _topRecentDiagnosticReasons(store.recentDiagnosticReasons),
      ...store.eventCounters,
    };
  }

  static Map<String, Object> _durationStatsSnapshot(
    String prefix,
    Iterable<Duration> samples,
  ) {
    if (samples.isEmpty) {
      return {
        '${prefix}_avg_time_ms': 0.0,
        '${prefix}_p95_time_ms': 0,
        '${prefix}_p99_time_ms': 0,
        '${prefix}_max_recent_time_ms': 0,
        '${prefix}_sample_count': 0,
      };
    }

    final sorted = samples.map((d) => d.inMilliseconds).toList()..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    return {
      '${prefix}_avg_time_ms': total / sorted.length,
      '${prefix}_p95_time_ms': sorted[(sorted.length * 0.95).floor()],
      '${prefix}_p99_time_ms': sorted[(sorted.length * 0.99).floor()],
      '${prefix}_max_recent_time_ms': sorted.last,
      '${prefix}_sample_count': sorted.length,
    };
  }

  static Map<String, Object> _sqlExecutionModeStatsSnapshot(MetricsEventStore store) {
    final values = <String, Object>{};
    for (final entry in store.sqlExecutionTimesByMode.entries) {
      values.addAll(
        _durationStatsSnapshot(
          'sql_execution_${entry.key}',
          entry.value,
        ),
      );
    }
    return values;
  }

  static Map<String, Object> _sqlExecutionModeNestedStatsSnapshot(MetricsEventStore store) {
    final values = <String, Object>{};
    for (final entry in store.sqlExecutionTimesByMode.entries) {
      final stats = _durationStatsSnapshot('', entry.value);
      values[entry.key] = {
        'avg_time_ms': stats['_avg_time_ms'] ?? 0.0,
        'p95_time_ms': stats['_p95_time_ms'] ?? 0,
        'p99_time_ms': stats['_p99_time_ms'] ?? 0,
        'max_recent_time_ms': stats['_max_recent_time_ms'] ?? 0,
        'sample_count': entry.value.length,
        'ops_per_second': _opsPerSecondForMode(store, entry.key),
      };
    }
    return values;
  }

  static double _opsPerSecondForMode(MetricsEventStore store, String mode) {
    final timestamps = store.sqlExecutionTimestampsByMode[mode];
    if (timestamps == null || timestamps.isEmpty) {
      return 0;
    }
    if (timestamps.length == 1) {
      return 1;
    }
    final windowSeconds = timestamps.last.difference(timestamps.first).inMilliseconds / 1000;
    if (windowSeconds <= 0) {
      return timestamps.length.toDouble();
    }
    return timestamps.length / windowSeconds;
  }

  static Map<String, int> _topRecentDiagnosticReasons(Queue<String> recentDiagnosticReasons) {
    final counts = <String, int>{};
    for (final reason in recentDiagnosticReasons) {
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount == 0 ? a.key.compareTo(b.key) : byCount;
      });
    return Map<String, int>.fromEntries(entries.take(10));
  }
}
