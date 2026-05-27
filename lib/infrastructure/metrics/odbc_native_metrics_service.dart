import 'dart:developer' as developer;

import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_diagnostics_snapshot_collector.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_event_bridge.dart';
import 'package:plug_agente/infrastructure/pool/odbc_native_connection_pool.dart';
import 'package:result_dart/result_dart.dart';

/// Collects native diagnostics snapshots from `odbc_fast`.
class OdbcNativeMetricsService implements IOdbcDiagnosticsSnapshotCollector {
  OdbcNativeMetricsService(
    this._service, {
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IConnectionPool? connectionPool,
    IOdbcConnectionSettings? settings,
    OdbcRuntimeTuning? runtimeTuning,
    MetricsCollector? metricsCollector,
    OdbcEventBridge? eventBridge,
  }) : _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _connectionPool = connectionPool,
       _settings = settings,
       _runtimeTuning = runtimeTuning,
       _metricsCollector = metricsCollector,
       _eventBridge = eventBridge;

  final OdbcService _service;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final IConnectionPool? _connectionPool;
  final IOdbcConnectionSettings? _settings;
  final OdbcRuntimeTuning? _runtimeTuning;
  final MetricsCollector? _metricsCollector;
  final OdbcEventBridge? _eventBridge;
  bool _loggedAsyncWorkerPoolSaturation = false;

  static const int _asyncPendingWarningThresholdPercent = 80;

  @override
  Future<Result<Map<String, dynamic>>> collectSnapshot() async {
    final metricsFuture = _service.getMetrics();
    final preparedFuture = _service.getPreparedStatementsMetrics();
    final metricsResult = await metricsFuture;
    if (metricsResult.isError()) {
      return Failure(
        OdbcFailureMapper.mapConnectionError(
          metricsResult.exceptionOrNull()!,
          operation: 'odbc_get_metrics',
        ),
      );
    }

    final preparedResult = await preparedFuture;
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
    final resolvedConnectionString = await _resolveConnectionString();
    final validationFuture = _collectValidationSnapshot(
      resolvedConnectionString,
    );
    final capabilitiesFuture = _collectCapabilitiesSnapshot(
      resolvedConnectionString,
    );
    final nativePoolFuture = _collectNativePoolSnapshot(
      resolvedConnectionString,
    );
    final appPoolFuture = _collectAppPoolSnapshot();
    final asyncWorkerPoolFuture = _collectAsyncWorkerPoolSnapshot();
    final sqlQueueSnapshot = _collectSqlQueueSnapshot();
    final validationSnapshot = await validationFuture;
    final capabilitiesSnapshot = await capabilitiesFuture;
    final nativePoolSnapshot = await nativePoolFuture;
    final appPoolSnapshot = await appPoolFuture;
    final asyncWorkerPoolSnapshot = await asyncWorkerPoolFuture;

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
      'connection': validationSnapshot,
      'driver_capabilities': capabilitiesSnapshot,
      'app_pool': appPoolSnapshot,
      'native_pool': nativePoolSnapshot,
      'async_worker_pool': asyncWorkerPoolSnapshot,
      'runtime_tuning': _runtimeTuning?.toMap(),
      'sql_queue': sqlQueueSnapshot,
      'recent_odbc_events': _collectRecentOdbcEventsSnapshot(),
    });
  }

  Map<String, dynamic> _collectRecentOdbcEventsSnapshot() {
    final bridge = _eventBridge;
    if (bridge == null) {
      return const <String, dynamic>{'available': false};
    }
    final events = bridge.recentEvents;
    return <String, dynamic>{
      'available': true,
      'count': events.length,
      'events': events.map(_serializeOdbcEvent).toList(growable: false),
    };
  }

  Map<String, Object?> _serializeOdbcEvent(OdbcEvent event) {
    final base = <String, Object?>{
      'kind': event.runtimeType.toString(),
      'timestamp': event.timestamp.toIso8601String(),
    };
    switch (event) {
      case ConnectionLost(:final connectionId, :final reason):
        base['connection_id'] = connectionId;
        base['reason_type'] = reason.runtimeType.toString();
        base['reason_message'] = reason.toString();
      case AutoReconnectAttempted(:final connectionId, :final attempt, :final maxAttempts):
        base['connection_id'] = connectionId;
        base['attempt'] = attempt;
        base['max_attempts'] = maxAttempts;
      case WorkerRecovered():
        break;
      case PoolResize(:final poolId, :final oldSize, :final newSize):
        base['pool_id'] = poolId;
        base['old_size'] = oldSize;
        base['new_size'] = newSize;
      case SlowQueryDetected(:final connectionId, :final sql, :final durationMs):
        base['connection_id'] = connectionId;
        base['duration_ms'] = durationMs;
        base['sql_preview'] = sql.length > 80 ? '${sql.substring(0, 77)}...' : sql;
    }
    return base;
  }

  Future<String?> _resolveConnectionString() async {
    final resolver = _activeConfigResolver;
    if (resolver == null && _configRepository == null) {
      return null;
    }

    final configResult = resolver != null
        ? await resolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await _configRepository!.getCurrentConfigMetadata();
    return configResult.fold(
      (config) {
        final resolved = config.resolveConnectionString().trim();
        return resolved.isEmpty ? null : resolved;
      },
      (_) => null,
    );
  }

  Future<Map<String, dynamic>> _collectValidationSnapshot(
    String? connectionString,
  ) async {
    if (connectionString == null) {
      return const <String, dynamic>{'available': false};
    }

    final validationResult = await _service.validateConnectionString(
      connectionString,
    );
    return validationResult.fold(
      (_) => const <String, dynamic>{
        'available': true,
        'valid': true,
      },
      (error) => <String, dynamic>{
        'available': true,
        'valid': false,
        'error': error.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> _collectCapabilitiesSnapshot(
    String? connectionString,
  ) async {
    if (connectionString == null) {
      return const <String, dynamic>{'available': false};
    }

    final capabilitiesResult = await _service.getDriverCapabilities(
      connectionString,
    );
    return capabilitiesResult.fold(
      (capabilities) => <String, dynamic>{
        'available': true,
        ...capabilities,
      },
      (error) => <String, dynamic>{
        'available': false,
        'error': error.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> _collectNativePoolSnapshot(
    String? connectionString,
  ) async {
    final pool = _connectionPool;
    if (pool case final IConnectionPoolDiagnostics diagnosticsPool when pool is! OdbcNativeConnectionPool) {
      return <String, dynamic>{
        'available': true,
        'state_source': 'pool_diagnostics',
        ...diagnosticsPool.getHealthDiagnostics(),
      };
    }

    if (connectionString == null || pool is! OdbcNativeConnectionPool) {
      return const <String, dynamic>{'available': false};
    }

    final stateResult = await pool.getDetailedState(connectionString);
    return stateResult.fold(
      (state) => <String, dynamic>{...state},
      (error) => <String, dynamic>{
        'available': false,
        'error': error.toString(),
      },
    );
  }

  Future<Map<String, dynamic>> _collectAppPoolSnapshot() async {
    final pool = _connectionPool;
    if (pool == null) {
      return const <String, dynamic>{'available': false};
    }

    final diagnostics = pool is IConnectionPoolDiagnostics
        ? (pool as IConnectionPoolDiagnostics).getHealthDiagnostics()
        : const <String, Object?>{};
    final activeResult = await pool.getActiveCount();
    return activeResult.fold(
      (active) => <String, dynamic>{
        'available': true,
        'active_connections': active,
        if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
      },
      (error) => <String, dynamic>{
        'available': false,
        'error': error.toString(),
        if (diagnostics.isNotEmpty) 'diagnostics': diagnostics,
      },
    );
  }

  Future<Map<String, dynamic>> _collectAsyncWorkerPoolSnapshot() async {
    final stats = await _service.getWorkerPoolStats();
    if (stats == null) {
      return const <String, dynamic>{'available': false};
    }
    return _buildAsyncWorkerPoolSnapshot(stats);
  }

  Map<String, dynamic> _buildAsyncWorkerPoolSnapshot(
    AsyncWorkerPoolStats stats,
  ) {
    final maxPendingRequests =
        _runtimeTuning?.asyncMaxPendingRequests ?? (_settings == null ? null : _settings.poolSize * 4);
    final pendingSaturationPercent = maxPendingRequests == null || maxPendingRequests <= 0
        ? null
        : stats.pendingRequests / maxPendingRequests * 100;
    final isNearPendingLimit =
        pendingSaturationPercent != null && pendingSaturationPercent >= _asyncPendingWarningThresholdPercent;

    _logAsyncWorkerPoolSaturationIfNeeded(
      isNearPendingLimit: isNearPendingLimit,
      pendingRequests: stats.pendingRequests,
      maxPendingRequests: maxPendingRequests,
      pendingSaturationPercent: pendingSaturationPercent,
    );

    return <String, dynamic>{
      'available': true,
      'worker_count': stats.workerCount,
      'configured_worker_count': _runtimeTuning?.asyncWorkerCount,
      'max_pending_requests': maxPendingRequests,
      'pending_requests': stats.pendingRequests,
      'pending_saturation_percent': pendingSaturationPercent,
      'near_pending_limit': isNearPendingLimit,
      'active_requests': stats.activeRequests,
      'total_routed': stats.totalRouted,
      'completed': stats.completedRequests,
      'failed': stats.failedRequests,
      'timeouts': stats.timeouts,
      'fallbacks_to_blocking': stats.fallbacksToBlocking,
      'cancel_attempts': stats.cancelAttempts,
      'cancel_succeeded': stats.cancelSucceeded,
      'cancel_unsupported': stats.cancelUnsupported,
      'latency_avg_micros': stats.latencyAvgMicros,
      'latency_p95_micros': stats.latencyP95Micros,
      'latency_max_micros': stats.latencyMaxMicros,
      'queue_wait_avg_micros': stats.queueWaitAvgMicros,
      'queue_wait_p95_micros': stats.queueWaitP95Micros,
      'queue_wait_max_micros': stats.queueWaitMaxMicros,
      'execution_avg_micros': stats.executionAvgMicros,
      'execution_p95_micros': stats.executionP95Micros,
      'execution_max_micros': stats.executionMaxMicros,
      'workers': stats.workers.map(_workerStatsSnapshot).toList(growable: false),
    };
  }

  void _logAsyncWorkerPoolSaturationIfNeeded({
    required bool isNearPendingLimit,
    required int pendingRequests,
    required int? maxPendingRequests,
    required double? pendingSaturationPercent,
  }) {
    if (!isNearPendingLimit) {
      _loggedAsyncWorkerPoolSaturation = false;
      return;
    }
    if (_loggedAsyncWorkerPoolSaturation) {
      return;
    }

    _loggedAsyncWorkerPoolSaturation = true;
    developer.log(
      'ODBC async worker pool pending queue is near capacity',
      name: 'odbc_native_metrics',
      level: 900,
      error: <String, Object?>{
        'pending_requests': pendingRequests,
        'max_pending_requests': maxPendingRequests,
        'pending_saturation_percent': pendingSaturationPercent,
        'suggestion': 'Consider increasing ODBC_ASYNC_MAX_PENDING_REQUESTS or reducing upstream SQL concurrency.',
      },
    );
  }

  Map<String, dynamic> _workerStatsSnapshot(AsyncWorkerStats worker) {
    return <String, dynamic>{
      'index': worker.index,
      'pending_requests': worker.pendingRequests,
      'active_requests': worker.activeRequests,
      'total_routed': worker.totalRouted,
      'completed': worker.completedRequests,
      'failed': worker.failedRequests,
      'timeouts': worker.timeouts,
      'fallbacks_to_blocking': worker.fallbacksToBlocking,
      'cancel_attempts': worker.cancelAttempts,
      'cancel_succeeded': worker.cancelSucceeded,
      'cancel_unsupported': worker.cancelUnsupported,
      'latency_avg_micros': worker.latencyAvgMicros,
      'latency_p95_micros': worker.latencyP95Micros,
      'latency_max_micros': worker.latencyMaxMicros,
      'queue_wait_avg_micros': worker.queueWaitAvgMicros,
      'queue_wait_p95_micros': worker.queueWaitP95Micros,
      'queue_wait_max_micros': worker.queueWaitMaxMicros,
      'execution_avg_micros': worker.executionAvgMicros,
      'execution_p95_micros': worker.executionP95Micros,
      'execution_max_micros': worker.executionMaxMicros,
    };
  }

  Map<String, dynamic> _collectSqlQueueSnapshot() {
    final metricsCollector = _metricsCollector;
    if (metricsCollector == null) {
      return const <String, dynamic>{'available': false};
    }

    final metrics = metricsCollector.getSnapshot();
    return <String, dynamic>{
      'available': true,
      'current_size': metrics['sql_queue_current_size'] ?? 0,
      'max_observed_size': metrics['sql_queue_max_size'] ?? 0,
      'active_workers': metrics['sql_queue_current_workers'] ?? 0,
      'max_observed_workers': metrics['sql_queue_max_workers'] ?? 0,
      'rejections_total': metrics['sql_queue_rejection_count'] ?? 0,
      'timeouts_total': metrics['sql_queue_timeout_count'] ?? 0,
      'avg_wait_time_ms': metrics['sql_queue_avg_wait_time_ms'] ?? 0,
      'p95_wait_time_ms': metrics['sql_queue_p95_wait_time_ms'] ?? 0,
      'max_recent_wait_time_ms': metrics['sql_queue_max_recent_wait_time_ms'] ?? 0,
      'pool_wait_timeouts_total': metrics['pool_acquire_timeout_count'] ?? 0,
    };
  }
}
