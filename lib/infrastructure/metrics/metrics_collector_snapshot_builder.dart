import 'dart:collection';

import 'package:plug_agente/core/constants/metrics_sampling_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_duration_samples.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';

/// Builds health snapshots while caching the sorting-heavy latency aggregates.
final class MetricsCollectorSnapshotBuilder {
  MetricsCollectorSnapshotBuilder({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  DateTime? _expensiveSnapshotExpiresAt;
  Map<String, Object>? _cachedExpensiveSnapshot;

  void clear() {
    _expensiveSnapshotExpiresAt = null;
    _cachedExpensiveSnapshot = null;
  }

  Map<String, Object> build({
    required MetricsDurationSamples queryLatencySamples,
    required int queryCount,
    required int queryErrorCount,
    required MetricsEventStore store,
    required int sqlQueueRejectionCount,
    required int sqlQueueTimeoutCount,
    required int sqlQueueTimeoutAfterWorkerStartedCount,
    required int sqlQueueSaturation70Count,
    required int sqlQueueSaturation90Count,
    required int sqlQueueWorkersEqualPoolCount,
  }) {
    final now = _now();
    final cached = _cachedExpensiveSnapshot;
    final expensive =
        cached != null && _expensiveSnapshotExpiresAt != null && now.isBefore(_expensiveSnapshotExpiresAt!)
        ? cached
        : _refreshExpensiveSnapshot(
            queryLatencySamples,
            queryCount,
            queryErrorCount,
            store,
            now,
          );

    // Counters and gauges intentionally stay outside the cached aggregate.
    return {
      ...expensive,
      'query_count': queryCount,
      'query_error_count': queryErrorCount,
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
      'rpc_outbound_response_active': store.outboundResponseActive,
      'rpc_outbound_response_max_active': store.outboundResponseMaxActive,
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
      ...store.eventCounters,
    };
  }

  Map<String, Object> _refreshExpensiveSnapshot(
    MetricsDurationSamples queryLatencySamples,
    int queryCount,
    int queryErrorCount,
    MetricsEventStore store,
    DateTime now,
  ) {
    final values = <String, Object>{
      ..._queryStatsSnapshot(
        queryLatencySamples,
        queryCount,
        queryErrorCount,
      ),
      ..._sqlQueueWaitStats(store),
      ..._durationStatsSnapshot('agent_action_queue_wait', store.agentActionQueueWaitTimes),
      ..._durationStatsSnapshot('rpc_outbound_response_wait', store.outboundResponseWaitTimes),
      ..._durationStatsSnapshot('agent_action_execution', store.agentActionExecutionDurations),
      ..._durationStatsSnapshot('agent_action_process_start', store.agentActionProcessStartDurations),
      ..._durationStatsSnapshot('pool_wait', store.poolWaitTimes),
      ..._durationStatsSnapshot('direct_connection_wait', store.directConnectionWaitTimes),
      ..._durationStatsSnapshot('read_only_batch_parallel_wait', store.readOnlyBatchParallelWaitTimes),
      ..._durationStatsSnapshot('streaming_worker_hold', store.streamingWorkerHoldTimes),
      ..._durationStatsSnapshot('connect', store.connectTimes),
      ..._durationStatsSnapshot('sql_execution', store.sqlExecutionTimes),
      ..._durationStatsSnapshot('auto_update_probe', store.autoUpdateProbeTimes),
      ..._durationStatsSnapshot('auto_update_download', store.autoUpdateDownloadTimes),
      ..._durationStatsSnapshot('prepared_prepare', store.preparedPrepareTimes),
      ..._sqlExecutionModeStatsSnapshot(store),
      'sql_execution_by_mode': _sqlExecutionModeNestedStatsSnapshot(store),
      'top_recent_diagnostic_reasons': _topRecentDiagnosticReasons(store.recentDiagnosticReasons),
    };
    _cachedExpensiveSnapshot = Map<String, Object>.unmodifiable(values);
    _expensiveSnapshotExpiresAt = now.add(MetricsSamplingConstants.percentileSnapshotCacheTtl);
    return _cachedExpensiveSnapshot!;
  }

  Map<String, Object> _queryStatsSnapshot(
    Iterable<Duration> queryLatencySamples,
    int queryCount,
    int queryErrorCount,
  ) {
    final latencies = queryLatencySamples.map((sample) => sample.inMilliseconds).toList()..sort();
    final totalLatency = latencies.fold<int>(0, (sum, value) => sum + value);
    return {
      'query_count': queryCount,
      'query_error_count': queryErrorCount,
      'query_avg_latency_ms': latencies.isEmpty ? 0.0 : totalLatency / latencies.length,
      'query_p95_latency_ms': _percentile(latencies, 0.95),
      'query_p99_latency_ms': _percentile(latencies, 0.99),
    };
  }

  Map<String, Object> _sqlQueueWaitStats(MetricsEventStore store) {
    final sorted = store.queueWaitTimes.map((sample) => sample.inMilliseconds).toList()..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    return {
      'sql_queue_avg_wait_time_ms': sorted.isEmpty ? 0.0 : total / sorted.length,
      'sql_queue_p95_wait_time_ms': _percentile(sorted, 0.95),
      'sql_queue_max_recent_wait_time_ms': sorted.isEmpty ? 0 : sorted.last,
    };
  }

  Map<String, Object> _durationStatsSnapshot(String prefix, Iterable<Duration> samples) {
    final sorted = samples.map((sample) => sample.inMilliseconds).toList()..sort();
    final total = sorted.fold<int>(0, (sum, value) => sum + value);
    return {
      '${prefix}_avg_time_ms': sorted.isEmpty ? 0.0 : total / sorted.length,
      '${prefix}_p95_time_ms': _percentile(sorted, 0.95),
      '${prefix}_p99_time_ms': _percentile(sorted, 0.99),
      '${prefix}_max_recent_time_ms': sorted.isEmpty ? 0 : sorted.last,
      '${prefix}_sample_count': sorted.length,
    };
  }

  Map<String, Object> _sqlExecutionModeStatsSnapshot(MetricsEventStore store) {
    final values = <String, Object>{};
    for (final entry in store.sqlExecutionTimesByMode.entries) {
      values.addAll(_durationStatsSnapshot('sql_execution_${entry.key}', entry.value));
    }
    return values;
  }

  Map<String, Object> _sqlExecutionModeNestedStatsSnapshot(MetricsEventStore store) {
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

  int _percentile(List<int> sorted, double percentile) =>
      sorted.isEmpty ? 0 : sorted[(sorted.length * percentile).floor()];

  double _opsPerSecondForMode(MetricsEventStore store, String mode) {
    final timestamps = store.sqlExecutionTimestampsByMode[mode];
    if (timestamps == null || timestamps.isEmpty) return 0;
    if (timestamps.length == 1) return 1;
    final windowSeconds = timestamps.last.difference(timestamps.first).inMilliseconds / 1000;
    return windowSeconds <= 0 ? timestamps.length.toDouble() : timestamps.length / windowSeconds;
  }

  Map<String, int> _topRecentDiagnosticReasons(Queue<String> reasons) {
    final counts = <String, int>{};
    for (final reason in reasons) {
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((left, right) {
        final byCount = right.value.compareTo(left.value);
        return byCount == 0 ? left.key.compareTo(right.key) : byCount;
      });
    return Map<String, int>.fromEntries(entries.take(10));
  }
}
