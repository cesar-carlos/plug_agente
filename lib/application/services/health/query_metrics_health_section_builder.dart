import 'package:plug_agente/application/services/health/health_metric_helpers.dart';

final class QueryMetricsHealthSectionBuilder {
  const QueryMetricsHealthSectionBuilder();

  Map<String, Object?> buildPrepared(Map<String, Object?> metrics) {
    return {
      'reuse_total': metrics['prepared_statement_reuse'] ?? 0,
      'cache_hit_total': metrics['prepared_statement_cache_hit'] ?? 0,
      'cache_miss_total': metrics['prepared_statement_cache_miss'] ?? 0,
      'prepare_avg_ms': (metrics['prepared_prepare_avg_time_ms'] as num?)?.toDouble() ?? 0,
      'prepare_p95_ms': (metrics['prepared_prepare_p95_time_ms'] as num?)?.toInt() ?? 0,
    };
  }

  Map<String, Object?> buildTimeouts(Map<String, Object?> metrics) {
    return {
      'sql_total': metrics['query_timeout'] ?? 0,
      'pool_total':
          (metrics['pool_acquire_timeout'] as int? ?? 0) +
          (metrics['direct_connection_acquire_timeout'] as int? ?? 0),
      'cancel_success_total': metrics['timeout_cancel_success'] ?? 0,
      'cancel_failure_total': metrics['timeout_cancel_failure'] ?? 0,
    };
  }

  Map<String, Object?> buildQueries(Map<String, Object?> metrics) {
    return {
      'total': metrics['query_count'] ?? 0,
      'errors': metrics['query_error_count'] ?? 0,
      'success_rate': healthQuerySuccessRate(
        metrics['query_count'] as int? ?? 0,
        metrics['query_error_count'] as int? ?? 0,
      ),
      'avg_latency_ms': (metrics['query_avg_latency_ms'] as num?)?.toInt() ?? 0,
      'p95_latency_ms': (metrics['query_p95_latency_ms'] as num?)?.toInt() ?? 0,
      'p99_latency_ms': (metrics['query_p99_latency_ms'] as num?)?.toInt() ?? 0,
    };
  }

  Map<String, Object?> buildBatch(Map<String, Object?> metrics) {
    return {
      'read_only_parallel_total': metrics['read_only_batch_parallel'] ?? 0,
      'read_only_parallel_capped_total': metrics['read_only_batch_parallel_capped'] ?? 0,
      'read_only_native_pool_total': metrics['read_only_batch_native_pool_path'] ?? 0,
      'read_only_native_pool_fallback_total': metrics['read_only_batch_native_pool_fallback'] ?? 0,
      'transactional_direct_total': metrics['transactional_batch_direct_path'] ?? 0,
      'transactional_native_pool_total': metrics['transactional_batch_native_pool_path'] ?? 0,
      'transactional_native_pool_fallback_total': metrics['transactional_batch_native_pool_fallback'] ?? 0,
      'bulk_insert_recommended_total': metrics['batch_bulk_insert_recommended'] ?? 0,
      'bulk_insert_routed_total': metrics['batch_bulk_insert_routed'] ?? 0,
      'last_requested_parallelism': metrics['read_only_batch_parallel_last_requested'] ?? 0,
      'last_effective_parallelism': metrics['read_only_batch_parallel_last_effective'] ?? 0,
      'parallel_global_wait_avg_ms': metrics['read_only_batch_parallel_wait_avg_time_ms'] ?? 0.0,
      'parallel_global_wait_p95_ms': metrics['read_only_batch_parallel_wait_p95_time_ms'] ?? 0,
      'parallel_global_wait_p99_ms': metrics['read_only_batch_parallel_wait_p99_time_ms'] ?? 0,
      'parallel_global_wait_sample_count': metrics['read_only_batch_parallel_wait_sample_count'] ?? 0,
    };
  }

  Map<String, Object?> buildDiagnostics(Map<String, Object?> metrics) {
    return {
      'top_recent_reasons': metrics['top_recent_diagnostic_reasons'] ?? const <String, int>{},
      'recent_reasons': metrics['recent_diagnostic_reasons'] ?? const <String>[],
    };
  }
}
