import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_direct_connection_limiter_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

/// Service for reporting application health and metrics.
class HealthService {
  HealthService({
    required MetricsCollector metricsCollector,
    required IDatabaseGateway gateway,
    IOdbcConnectionSettings? odbcSettings,
    IConnectionPool? connectionPool,
    IAgentConfigRepository? configRepository,
    IStreamingDatabaseGateway? streamingGateway,
    IDirectConnectionLimiterDiagnostics? directConnectionLimiter,
    FeatureFlags? featureFlags,
    Duration poolSnapshotTtl = const Duration(seconds: 2),
  }) : _metrics = metricsCollector,
       _gateway = gateway,
       _odbcSettings = odbcSettings,
       _connectionPool = connectionPool,
       _configRepository = configRepository,
       _streamingGateway = streamingGateway,
       _directConnectionLimiter = directConnectionLimiter,
       _featureFlags = featureFlags,
       _poolSnapshotTtl = poolSnapshotTtl;

  final MetricsCollector _metrics;
  final IDatabaseGateway _gateway;
  final IOdbcConnectionSettings? _odbcSettings;
  final IConnectionPool? _connectionPool;
  final IAgentConfigRepository? _configRepository;
  final IStreamingDatabaseGateway? _streamingGateway;
  final IDirectConnectionLimiterDiagnostics? _directConnectionLimiter;
  final FeatureFlags? _featureFlags;
  final Duration _poolSnapshotTtl;
  Future<String?>? _driverTypeResolution;
  String? _cachedDriverType;
  Future<_PoolHealthSnapshot>? _poolSnapshotResolution;
  _PoolHealthSnapshot? _cachedPoolSnapshot;

  /// Gets current health status with system metrics.
  Map<String, Object?> getHealthStatus() {
    return _buildHealthStatus();
  }

  /// Gets current health status with async pool diagnostics when available.
  Future<Map<String, Object?>> getHealthStatusAsync() async {
    final pool = _connectionPool;
    final poolSnapshot = await _resolvePoolSnapshot(pool);
    final poolDiagnostics = poolSnapshot.diagnostics;
    final driverType = poolDiagnostics['driver_type'] as String? ?? await _resolveDriverType();
    if (pool == null) {
      return _buildHealthStatus(
        poolDiagnostics: poolDiagnostics,
        driverType: driverType,
      );
    }

    return _buildHealthStatus(
      poolActiveCount: poolSnapshot.activeCount,
      poolDiagnostics: poolDiagnostics,
      driverType: driverType,
    );
  }

  Future<_PoolHealthSnapshot> _resolvePoolSnapshot(IConnectionPool? pool) async {
    final cached = _cachedPoolSnapshot;
    if (cached != null && DateTime.now().difference(cached.capturedAt) < _poolSnapshotTtl) {
      return cached;
    }

    final inFlight = _poolSnapshotResolution;
    if (inFlight != null) {
      return inFlight;
    }

    final resolution = _loadPoolSnapshot(pool);
    _poolSnapshotResolution = resolution;
    try {
      final snapshot = await resolution;
      _cachedPoolSnapshot = snapshot;
      return snapshot;
    } finally {
      _poolSnapshotResolution = null;
    }
  }

  Future<_PoolHealthSnapshot> _loadPoolSnapshot(IConnectionPool? pool) async {
    final diagnostics = switch (pool) {
      final IConnectionPoolDiagnostics diagnosticsPool => diagnosticsPool.getHealthDiagnostics(),
      _ => const <String, Object?>{},
    };

    if (pool == null) {
      return _PoolHealthSnapshot(
        diagnostics: diagnostics,
        capturedAt: DateTime.now(),
      );
    }

    final activeCountResult = await pool.getActiveCount();
    return _PoolHealthSnapshot(
      activeCount: activeCountResult.getOrNull(),
      diagnostics: diagnostics,
      capturedAt: DateTime.now(),
    );
  }

  Map<String, Object?> _buildHealthStatus({
    int? poolActiveCount,
    Map<String, Object?> poolDiagnostics = const <String, Object?>{},
    String? driverType,
  }) {
    final metrics = _metrics.getSnapshot();
    final queuedGateway = _gateway is QueuedDatabaseGateway ? _gateway : null;
    final directFallbacks = metrics['direct_connection_fallback'] as int? ?? 0;
    final nativeFallbacks = metrics['odbc_native_pool_fallback'] as int? ?? 0;

    return {
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
      'version': AppConstants.appVersion,
      'pool': {
        'size': _odbcSettings?.poolSize ?? ConnectionConstants.poolSize,
        'active_count': poolActiveCount,
        'acquire_timeout_seconds': ConnectionConstants.defaultPoolAcquireTimeout.inSeconds,
        'native_pool_exposed': poolDiagnostics['native_pool_exposed'] ?? false,
        'strategy': poolDiagnostics['strategy'] ?? 'lease',
        'effective_strategy': poolDiagnostics['effective_strategy'] ?? poolDiagnostics['strategy'] ?? 'lease',
        'driver_type': driverType,
        'experimental_enabled': poolDiagnostics['experimental_enabled'] ?? false,
        'native_eligible': poolDiagnostics['native_eligible'],
        'native_circuit_open': poolDiagnostics['native_circuit_open'] ?? false,
        'native_circuit_failures': poolDiagnostics['native_circuit_failures'] ?? 0,
        'native_circuit_disabled_until': poolDiagnostics['native_circuit_disabled_until'],
        'native_options_skip_total': poolDiagnostics['native_options_skip_total'] ?? 0,
        'native_execution_fallback_total': poolDiagnostics['native_execution_fallback_total'] ?? 0,
        'native_compatible_acquire_attempt_total':
            poolDiagnostics['native_compatible_acquire_attempt_total'] ??
            metrics['odbc_native_compatible_acquire_attempt'] ??
            0,
        'native_compatible_acquire_success_total':
            poolDiagnostics['native_compatible_acquire_success_total'] ??
            metrics['odbc_native_compatible_acquire_success'] ??
            0,
        'native_skip_reason': poolDiagnostics['native_skip_reason'],
        'fallbacks_total': directFallbacks + nativeFallbacks,
        'direct_fallbacks_total': directFallbacks,
        'native_fallbacks_total': nativeFallbacks,
      },
      'streaming': _buildStreamingHealth(metrics),
      'direct_connections': _buildDirectConnectionHealth(metrics),
      'sql_queue': queuedGateway != null
          ? {
              'enabled': true,
              'current_size': queuedGateway.queueSize,
              'max_size': queuedGateway.maxQueueSize,
              'active_workers': queuedGateway.activeWorkers,
              'max_workers': queuedGateway.maxWorkers,
              'active_batch_workers': queuedGateway.activeBatchWorkers,
              'max_batch_workers': queuedGateway.maxBatchWorkers,
              'active_long_query_workers': queuedGateway.activeLongQueryWorkers,
              'max_long_query_workers': queuedGateway.maxLongQueryWorkers,
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
      'prepared': {
        'reuse_total': metrics['prepared_statement_reuse'] ?? 0,
        'cache_hit_total': metrics['prepared_statement_cache_hit'] ?? 0,
        'cache_miss_total': metrics['prepared_statement_cache_miss'] ?? 0,
        'prepare_avg_ms': (metrics['prepared_prepare_avg_time_ms'] as num?)?.toDouble() ?? 0,
        'prepare_p95_ms': (metrics['prepared_prepare_p95_time_ms'] as num?)?.toInt() ?? 0,
      },
      'timeouts': {
        'sql_total': metrics['query_timeout'] ?? 0,
        'pool_total':
            (metrics['pool_acquire_timeout'] as int? ?? 0) +
            (metrics['direct_connection_acquire_timeout'] as int? ?? 0),
        'cancel_success_total': metrics['timeout_cancel_success'] ?? 0,
        'cancel_failure_total': metrics['timeout_cancel_failure'] ?? 0,
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
      'diagnostics': {
        'top_recent_reasons': metrics['top_recent_diagnostic_reasons'] ?? const <String, int>{},
        'recent_reasons': metrics['recent_diagnostic_reasons'] ?? const <String>[],
      },
      'uptime_seconds': AppUptime.uptimeSeconds,
    };
  }

  Future<String?> _resolveDriverType() async {
    final cachedDriverType = _cachedDriverType;
    if (cachedDriverType != null) {
      return cachedDriverType;
    }

    final inFlightResolution = _driverTypeResolution;
    if (inFlightResolution != null) {
      return inFlightResolution;
    }

    final resolution = _loadDriverType();
    _driverTypeResolution = resolution;
    try {
      final driverType = await resolution;
      if (driverType != null) {
        _cachedDriverType = driverType;
      }
      return driverType;
    } finally {
      _driverTypeResolution = null;
    }
  }

  Map<String, Object?> _buildStreamingHealth(Map<String, Object?> metrics) {
    final gateway = _streamingGateway;
    final diagnostics = switch (gateway) {
      final IStreamingGatewayDiagnostics streamingDiagnostics => streamingDiagnostics.getStreamingDiagnostics(),
      _ => const <String, Object?>{},
    };
    final dbStreamingFlag = _featureFlags?.enableSocketStreamingFromDb ?? false;
    final chunkStreamingFlag = _featureFlags?.enableSocketStreamingChunks ?? false;
    final effectiveDbStreamingEnabled = gateway != null && dbStreamingFlag;

    return {
      'enabled': effectiveDbStreamingEnabled,
      'gateway_available': diagnostics['enabled'] ?? gateway != null,
      'db_streaming_flag_enabled': dbStreamingFlag,
      'chunk_streaming_flag_enabled': chunkStreamingFlag,
      'auto_db_streaming_policy_enabled': dbStreamingFlag && !chunkStreamingFlag,
      'active_streams': diagnostics['active_streams'] ?? (gateway?.hasActiveStream ?? false ? 1 : 0),
      'from_db_responses_total': metrics['rpc_sql_execute_streaming_from_db_response'] ?? 0,
      'auto_from_db_responses_total': metrics['rpc_sql_execute_auto_streaming_from_db_response'] ?? 0,
      'chunked_materialized_responses_total': metrics['rpc_sql_execute_streaming_chunks_response'] ?? 0,
      'materialized_responses_total': metrics['rpc_sql_execute_materialized_response'] ?? 0,
      'cancel_requests_total': metrics['stream_cancel_request'] ?? 0,
      'backpressure_cancels_total': metrics['stream_cancel_backpressure'] ?? 0,
    };
  }

  Map<String, Object?> _buildDirectConnectionHealth(Map<String, Object?> metrics) {
    final limiter = _directConnectionLimiter;

    return {
      'active_count': limiter?.activeCount ?? metrics['direct_connection_active_count'] ?? 0,
      'max_concurrent': limiter?.maxConcurrent,
      'is_saturated': limiter?.isSaturated ?? false,
      'opened_total': limiter?.openedTotal ?? metrics['direct_connection_opened'] ?? 0,
      'closed_total': limiter?.closedTotal ?? metrics['direct_connection_closed'] ?? 0,
      'acquire_timeouts_total': metrics['direct_connection_acquire_timeout'] ?? 0,
    };
  }

  Future<String?> _loadDriverType() async {
    final repository = _configRepository;
    if (repository == null) {
      return null;
    }

    final configResult = await repository.getCurrentConfig();
    return configResult.fold(
      (config) => switch (DatabaseDriver.fromString(config.driverName)) {
        DatabaseDriver.sqlServer => 'sqlServer',
        DatabaseDriver.postgreSQL => 'postgresql',
        DatabaseDriver.sqlAnywhere => 'sybaseAnywhere',
        DatabaseDriver.unknown => null,
      },
      (_) => null,
    );
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

final class _PoolHealthSnapshot {
  const _PoolHealthSnapshot({
    required this.diagnostics,
    required this.capturedAt,
    this.activeCount,
  });

  final int? activeCount;
  final Map<String, Object?> diagnostics;
  final DateTime capturedAt;
}
