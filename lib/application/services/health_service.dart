import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Service for reporting application health and metrics.
class HealthService {
  HealthService({
    required MetricsCollector metricsCollector,
    required IDatabaseGateway gateway,
  })  : _metrics = metricsCollector,
        _gateway = gateway;

  final MetricsCollector _metrics;
  final IDatabaseGateway _gateway;

  /// Gets current health status with system metrics.
  Map<String, Object?> getHealthStatus() {
    final metrics = _metrics.getSnapshot();
    final queuedGateway =
        _gateway is QueuedDatabaseGateway ? _gateway : null;

    return {
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
      'version': AppConstants.appVersion,
      'pool': {
        'size': ConnectionConstants.poolSize,
      },
      'sql_queue': queuedGateway != null
          ? {
              'enabled': true,
              'current_size': queuedGateway.queueSize,
              'max_size': ConnectionConstants.sqlQueueMaxSize,
              'active_workers': queuedGateway.activeWorkers,
              'max_workers': ConnectionConstants.sqlQueueMaxWorkers,
              'rejections_total': metrics['sql_queue_rejection_count'] ?? 0,
              'timeouts_total': metrics['sql_queue_timeout_count'] ?? 0,
              'avg_wait_time_ms': (metrics['sql_queue_avg_wait_time_ms'] as num?)?.toInt() ?? 0,
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
