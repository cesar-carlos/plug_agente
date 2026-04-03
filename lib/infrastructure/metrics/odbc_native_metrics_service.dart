import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:result_dart/result_dart.dart';

/// Collects native diagnostics snapshots from `odbc_fast`.
class OdbcNativeMetricsService {
  OdbcNativeMetricsService(this._service);

  final OdbcService _service;

  Future<Result<Map<String, dynamic>>> collectSnapshot() async {
    final metricsResult = await _service.getMetrics();
    if (metricsResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          metricsResult.exceptionOrNull()!,
          operation: 'odbc_get_metrics',
        ),
      );
    }

    final preparedResult = await _service.getPreparedStatementsMetrics();
    if (preparedResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          preparedResult.exceptionOrNull()!,
          operation: 'odbc_get_prepared_metrics',
        ),
      );
    }

    final metrics = metricsResult.getOrThrow();
    final prepared = preparedResult.getOrThrow();
    return Success(<String, dynamic>{
      'engine': <String, dynamic>{
        'query_count': metrics.queryCount,
        'error_count': metrics.errorCount,
        'uptime_secs': metrics.uptimeSecs,
        'total_latency_millis': metrics.totalLatencyMillis,
        'avg_latency_millis': metrics.avgLatencyMillis,
      },
      'prepared_statements': <String, dynamic>{
        'cache_size': prepared.cacheSize,
        'cache_max_size': prepared.cacheMaxSize,
        'cache_hits': prepared.cacheHits,
        'cache_misses': prepared.cacheMisses,
        'total_prepares': prepared.totalPrepares,
        'total_executions': prepared.totalExecutions,
        'memory_usage_bytes': prepared.memoryUsageBytes,
        'avg_executions_per_stmt': prepared.avgExecutionsPerStmt,
        'cache_hit_rate': prepared.cacheHitRate,
        'cache_miss_rate': prepared.cacheMissRate,
        'cache_utilization': prepared.cacheUtilization,
      },
    });
  }
}
