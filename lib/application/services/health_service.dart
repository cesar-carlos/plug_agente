import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Service for reporting application health and metrics.
class HealthService {
  HealthService({
    required MetricsCollector metricsCollector,
    required IDatabaseGateway gateway,
    IOdbcConnectionSettings? odbcSettings,
    IConnectionPool? connectionPool,
  }) : _metrics = metricsCollector,
       _gateway = gateway,
       _odbcSettings = odbcSettings,
       _connectionPool = connectionPool;

  final MetricsCollector _metrics;
  final IDatabaseGateway _gateway;
  final IOdbcConnectionSettings? _odbcSettings;
  final IConnectionPool? _connectionPool;

  /// Gets current health status with system metrics.
  Map<String, Object?> getHealthStatus() {
    return _buildHealthStatus(poolActiveCount: null);
  }

  /// Gets current health status with async pool diagnostics when available.
  Future<Map<String, Object?>> getHealthStatusAsync() async {
    final pool = _connectionPool;
    if (pool == null) {
      return _buildHealthStatus(poolActiveCount: null);
    }

    final activeCountResult = await pool.getActiveCount();
    return _buildHealthStatus(
      poolActiveCount: activeCountResult.getOrNull(),
    );
  }

  Map<String, Object?> _buildHealthStatus({required int? poolActiveCount}) {
    final metrics = _metrics.getSnapshot();
    final queuedGateway = _gateway is QueuedDatabaseGateway ? _gateway : null;

    return {
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
      'version': AppConstants.appVersion,
      'pool': {
        'size': _odbcSettings?.poolSize ?? ConnectionConstants.poolSize,
        'active_count': poolActiveCount,
        'acquire_timeout_seconds': ConnectionConstants.defaultPoolAcquireTimeout.inSeconds,
        'native_pool_exposed': false,
      },
      'sql_queue': queuedGateway != null
          ? {
              'enabled': true,
              'current_size': queuedGateway.queueSize,
              'max_size': queuedGateway.maxQueueSize,
              'active_workers': queuedGateway.activeWorkers,
              'max_workers': queuedGateway.maxWorkers,
              'enqueue_timeout_seconds': queuedGateway.enqueueTimeout.inSeconds,
              'rejections_total': metrics['sql_queue_rejection_count'] ?? 0,
              'timeouts_total': metrics['sql_queue_timeout_count'] ?? 0,
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
            }
          : {
              'enabled': false,
            },
      'queries': {
        'total': metrics['query_count'] ?? 0,
        'errors': metrics['query_error_count'] ?? 0,
        'success_rate': _calculateSuccessRate(
          metrics['query_count'] as int? ?? 0,
          metrics['query_error_count'] as int? ?? 0,
        ),
        'avg_latency_ms': (metrics['query_avg_latency_ms'] as num?)?.toInt() ?? 0,
        'p95_latency_ms': (metrics['query_p95_latency_ms'] as num?)?.toInt() ?? 0,
        'p99_latency_ms': (metrics['query_p99_latency_ms'] as num?)?.toInt() ?? 0,
      },
      'uptime_seconds': AppUptime.uptimeSeconds,
    };
  }

  /// Gets detailed metrics for monitoring/debugging.
  Map<String, Object?> getDetailedMetrics() {
    return _metrics.getSnapshot();
  }

  double _calculateSuccessRate(int total, int errors) {
    if (total == 0) {
      return 100;
    }
    final successful = total - errors;
    return (successful / total * 100).clamp(0, 100);
  }
}
