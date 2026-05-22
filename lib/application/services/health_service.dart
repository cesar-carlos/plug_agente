import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_direct_connection_limiter_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';

/// Service for reporting application health and metrics.
class HealthService {
  HealthService({
    required IMetricsCollector metricsCollector,
    required IDatabaseGateway gateway,
    IOdbcConnectionSettings? odbcSettings,
    IConnectionPool? connectionPool,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IStreamingDatabaseGateway? streamingGateway,
    IDirectConnectionLimiterDiagnostics? directConnectionLimiter,
    FeatureFlags? featureFlags,
    OdbcRuntimeTuning? odbcRuntimeTuning,
    AgentRuntimeIdentity? agentRuntimeIdentity,
    AgentActionLocalRunnerRegistry? agentActionRunnerRegistry,
    AgentActionRuntimeStateGuard? agentActionRuntimeStateGuard,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    AgentActionRetentionSettings? agentActionRetentionSettings,
    AgentActionTriggerScheduler? agentActionTriggerScheduler,
    IAgentActionSchedulerInstanceLock? agentActionSchedulerInstanceLock,
    IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics,
    Duration poolSnapshotTtl = const Duration(seconds: 2),
  }) : _metrics = metricsCollector,
       _gateway = gateway,
       _odbcSettings = odbcSettings,
       _connectionPool = connectionPool,
       _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _streamingGateway = streamingGateway,
       _directConnectionLimiter = directConnectionLimiter,
       _featureFlags = featureFlags,
       _odbcRuntimeTuning = odbcRuntimeTuning,
       _agentRuntimeIdentity = agentRuntimeIdentity,
       _agentActionRunnerRegistry = agentActionRunnerRegistry,
       _agentActionRuntimeStateGuard = agentActionRuntimeStateGuard,
       _elevatedRunnerReadiness = elevatedRunnerReadiness,
       _agentActionRetentionSettings = agentActionRetentionSettings,
       _agentActionTriggerScheduler = agentActionTriggerScheduler,
       _agentActionSchedulerInstanceLock = agentActionSchedulerInstanceLock,
       _comObjectInvocationDiagnostics = comObjectInvocationDiagnostics,
       _poolSnapshotTtl = poolSnapshotTtl;

  final IMetricsCollector _metrics;
  final IDatabaseGateway _gateway;
  final IOdbcConnectionSettings? _odbcSettings;
  final IConnectionPool? _connectionPool;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final IStreamingDatabaseGateway? _streamingGateway;
  final IDirectConnectionLimiterDiagnostics? _directConnectionLimiter;
  final FeatureFlags? _featureFlags;
  final OdbcRuntimeTuning? _odbcRuntimeTuning;
  final AgentRuntimeIdentity? _agentRuntimeIdentity;
  final AgentActionLocalRunnerRegistry? _agentActionRunnerRegistry;
  final AgentActionRuntimeStateGuard? _agentActionRuntimeStateGuard;
  final ElevatedActionRunnerReadinessService? _elevatedRunnerReadiness;
  final AgentActionRetentionSettings? _agentActionRetentionSettings;
  final AgentActionTriggerScheduler? _agentActionTriggerScheduler;
  final IAgentActionSchedulerInstanceLock? _agentActionSchedulerInstanceLock;
  final IComObjectInvocationDiagnostics? _comObjectInvocationDiagnostics;
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

    final identity = _agentRuntimeIdentity;
    return {
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
      'version': AppConstants.appVersion,
      if (identity != null)
        'agent_runtime': <String, Object?>{
          'instance_id': identity.runtimeInstanceId,
          'session_id': identity.runtimeSessionId,
        },
      'odbc_runtime_tuning': _odbcRuntimeTuning?.toMap(),
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
              'active_non_query_workers': queuedGateway.activeNonQueryWorkers,
              'max_non_query_workers': queuedGateway.maxNonQueryWorkers,
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
      'sql_execution_by_mode': metrics['sql_execution_by_mode'] ?? const <String, Object>{},
      'batch': {
        'read_only_parallel_total': metrics['read_only_batch_parallel'] ?? 0,
        'read_only_parallel_capped_total': metrics['read_only_batch_parallel_capped'] ?? 0,
        'transactional_direct_total': metrics['transactional_batch_direct_path'] ?? 0,
        'transactional_native_pool_total': metrics['transactional_batch_native_pool_path'] ?? 0,
        'transactional_native_pool_fallback_total': metrics['transactional_batch_native_pool_fallback'] ?? 0,
        'bulk_insert_recommended_total': metrics['batch_bulk_insert_recommended'] ?? 0,
        'last_requested_parallelism': metrics['read_only_batch_parallel_last_requested'] ?? 0,
        'last_effective_parallelism': metrics['read_only_batch_parallel_last_effective'] ?? 0,
        'parallel_global_wait_avg_ms': metrics['read_only_batch_parallel_wait_avg_time_ms'] ?? 0.0,
        'parallel_global_wait_p95_ms': metrics['read_only_batch_parallel_wait_p95_time_ms'] ?? 0,
        'parallel_global_wait_p99_ms': metrics['read_only_batch_parallel_wait_p99_time_ms'] ?? 0,
        'parallel_global_wait_sample_count': metrics['read_only_batch_parallel_wait_sample_count'] ?? 0,
      },
      'diagnostics': {
        'top_recent_reasons': metrics['top_recent_diagnostic_reasons'] ?? const <String, int>{},
        'recent_reasons': metrics['recent_diagnostic_reasons'] ?? const <String>[],
      },
      if (_buildAgentActionsHealth(metrics) case final Map<String, Object?> agentActions) 'agent_actions': agentActions,
      'uptime_seconds': AppUptime.uptimeSeconds,
    };
  }

  Map<String, Object?>? _buildAgentActionsHealth(Map<String, Object?> metrics) {
    final flags = _featureFlags;
    if (flags == null) {
      return null;
    }

    final enabled = flags.enableAgentActions;
    final snapshot = _agentActionRuntimeStateGuard?.snapshot;
    final supportedTypes = _agentActionSupportedTypeNames();
    final unavailableTypes =
        snapshot?.unavailableActionTypes.map((AgentActionType type) => type.name).toList(growable: false) ??
        const <String>[];
    final String statusName;
    if (!enabled) {
      statusName = AgentActionSubsystemStatus.disabled.name;
    } else {
      statusName = snapshot?.status.name ?? AgentActionSubsystemStatus.ready.name;
    }

    final queueCounters = <String, Object?>{
      'concurrency_reject_total': _metricInt(metrics, 'agent_action_queue_concurrency_reject'),
      'concurrency_ignore_total': _metricInt(metrics, 'agent_action_queue_concurrency_ignore'),
      'depth_full_total': _metricInt(metrics, 'agent_action_queue_depth_full'),
      'pending_enqueued_total': _metricInt(metrics, 'agent_action_queue_pending_enqueued'),
      'idempotent_replay_total': _metricInt(metrics, 'agent_action_queue_idempotent_replay'),
      'run_started_total': _metricInt(metrics, 'agent_action_queue_run_started'),
      'pending_wait_timeout_total': _metricInt(metrics, 'agent_action_queue_pending_wait_timeout'),
      'pending_cancelled_total': _metricInt(metrics, 'agent_action_queue_pending_cancelled'),
    };

    final queueWait = <String, Object?>{
      'avg_time_ms': (metrics['agent_action_queue_wait_avg_time_ms'] as num?)?.toDouble() ?? 0.0,
      'p95_time_ms': _metricInt(metrics, 'agent_action_queue_wait_p95_time_ms'),
      'p99_time_ms': _metricInt(metrics, 'agent_action_queue_wait_p99_time_ms'),
      'max_recent_time_ms': _metricInt(metrics, 'agent_action_queue_wait_max_recent_time_ms'),
      'sample_count': _metricInt(metrics, 'agent_action_queue_wait_sample_count'),
    };

    final remoteRpc = <String, Object?>{
      'run_success_total': _metricInt(metrics, 'rpc_remote_agent_action_run_success'),
      'run_error_total': _metricInt(metrics, 'rpc_remote_agent_action_run_error'),
      'run_notification_rejected_total': _metricInt(metrics, 'rpc_remote_agent_action_run_notification_rejected'),
      'validate_run_success_total': _metricInt(metrics, 'rpc_remote_agent_action_validate_run_success'),
      'validate_run_error_total': _metricInt(metrics, 'rpc_remote_agent_action_validate_run_error'),
      'validate_run_notification_rejected_total': _metricInt(
        metrics,
        'rpc_remote_agent_action_validate_run_notification_rejected',
      ),
      'cancel_success_total': _metricInt(metrics, 'rpc_remote_agent_action_cancel_success'),
      'cancel_error_total': _metricInt(metrics, 'rpc_remote_agent_action_cancel_error'),
      'cancel_notification_rejected_total': _metricInt(
        metrics,
        'rpc_remote_agent_action_cancel_notification_rejected',
      ),
      'get_execution_success_total': _metricInt(metrics, 'rpc_remote_agent_action_get_execution_success'),
      'get_execution_error_total': _metricInt(metrics, 'rpc_remote_agent_action_get_execution_error'),
      'get_execution_notification_rejected_total': _metricInt(
        metrics,
        'rpc_remote_agent_action_get_execution_notification_rejected',
      ),
      'batch_read_limit_rejected_total': _metricInt(
        metrics,
        'rpc_remote_agent_action_batch_read_limit_rejected',
      ),
    };

    final executionCounters = <String, Object?>{
      'terminal_succeeded_total': _metricInt(metrics, 'agent_action_execution_terminal_succeeded'),
      'terminal_failed_total': _metricInt(metrics, 'agent_action_execution_terminal_failed'),
      'terminal_skipped_total': _metricInt(metrics, 'agent_action_execution_terminal_skipped'),
      'terminal_cancelled_total': _metricInt(metrics, 'agent_action_execution_terminal_cancelled'),
      'terminal_killed_total': _metricInt(metrics, 'agent_action_execution_terminal_killed'),
      'terminal_timed_out_total': _metricInt(metrics, 'agent_action_execution_terminal_timed_out'),
      'terminal_interrupted_total': _metricInt(metrics, 'agent_action_execution_terminal_interrupted'),
      'terminal_unknown_total': _metricInt(metrics, 'agent_action_execution_terminal_unknown'),
      'remote_permission_denied_total': _metricInt(metrics, 'agent_action_remote_permission_denied'),
      'local_authorization_denied_total': _metricInt(metrics, 'agent_action_local_authorization_denied'),
      'remote_rate_limited_total': _metricInt(metrics, 'agent_action_remote_rate_limited'),
      'history_purge_total': _metricInt(metrics, 'agent_action_execution_history_purge'),
      'remote_audit_purge_total': _metricInt(metrics, 'agent_action_remote_audit_purge'),
      'rpc_idempotency_cache_purge_total': _metricInt(metrics, 'agent_action_rpc_idempotency_cache_purge'),
      'elevated_bridge_artifacts_purge_total': _metricInt(metrics, 'agent_action_elevated_bridge_artifacts_purge'),
      'remote_audit_execution_correlated_total': _metricInt(
        metrics,
        'agent_action_remote_audit_execution_correlated',
      ),
      'cancel_kill_failed_total': _metricInt(metrics, 'agent_action_cancel_kill_failed'),
      'cancel_kill_permission_denied_total': _metricInt(
        metrics,
        'agent_action_cancel_kill_permission_denied',
      ),
      'cancel_process_not_active_total': _metricInt(metrics, 'agent_action_cancel_process_not_active'),
      'cancel_process_id_mismatch_total': _metricInt(metrics, 'agent_action_cancel_process_id_mismatch'),
      'cancel_process_identity_mismatch_total': _metricInt(
        metrics,
        'agent_action_cancel_process_identity_mismatch',
      ),
      'cancel_process_identity_unavailable_total': _metricInt(
        metrics,
        'agent_action_cancel_process_identity_unavailable',
      ),
      'captured_stdout_truncated_total': _metricInt(metrics, 'agent_action_captured_output_stdout_truncated'),
      'captured_stderr_truncated_total': _metricInt(metrics, 'agent_action_captured_output_stderr_truncated'),
      'captured_stdout_bytes_total': _metricInt(metrics, 'agent_action_captured_output_stdout_bytes'),
      'captured_stderr_bytes_total': _metricInt(metrics, 'agent_action_captured_output_stderr_bytes'),
      'captured_output_cleared_total': _metricInt(metrics, 'agent_action_captured_output_cleared'),
      'elevated_status_file_terminal_total': _metricInt(metrics, 'agent_action_elevated_status_file_terminal'),
      'elevated_status_file_wait_timeout_total': _metricInt(
        metrics,
        'agent_action_elevated_status_file_wait_timeout',
      ),
    };

    final executionDurationMs = <String, Object?>{
      'avg_time_ms': (metrics['agent_action_execution_avg_time_ms'] as num?)?.toDouble() ?? 0.0,
      'p95_time_ms': _metricInt(metrics, 'agent_action_execution_p95_time_ms'),
      'p99_time_ms': _metricInt(metrics, 'agent_action_execution_p99_time_ms'),
      'max_recent_time_ms': _metricInt(metrics, 'agent_action_execution_max_recent_time_ms'),
      'sample_count': _metricInt(metrics, 'agent_action_execution_sample_count'),
    };

    return <String, Object?>{
      'enabled': enabled,
      'remote_enabled': flags.enableRemoteAgentActions,
      'remote_ad_hoc_enabled': flags.enableRemoteAdHocAgentActions,
      'elevated_enabled': flags.enableElevatedAgentActions,
      'elevated_runner_configured': _elevatedRunnerReadiness?.isConfigured ?? false,
      'elevated_runner_degraded': _elevatedRunnerReadiness?.isDegraded ?? false,
      if (_comObjectInvocationDiagnostics case final IComObjectInvocationDiagnostics comDiagnostics) ...{
        'com_object_handlers_registered_count': comDiagnostics.registeredHandlerCount,
        'com_object_invocation_ready': comDiagnostics.registeredHandlerCount > 0,
      },
      'maintenance_mode': flags.enableAgentActionsMaintenanceMode,
      'remote_audit_enabled': flags.enableAgentActionRemoteAudit,
      'status': statusName,
      'supported_types': supportedTypes,
      'unavailable_types': unavailableTypes,
      'queue_counters': queueCounters,
      'queue_wait_ms': queueWait,
      'execution_counters': executionCounters,
      'execution_duration_ms': executionDurationMs,
      'remote_rpc_counters': remoteRpc,
      if (_buildAgentActionRetentionHealth() case final Map<String, Object?> retention) 'retention': retention,
      if (_buildAgentActionSchedulerHealth() case final Map<String, Object?> scheduler) 'scheduler': scheduler,
    };
  }

  Map<String, Object?>? _buildAgentActionSchedulerHealth() {
    final scheduler = _agentActionTriggerScheduler;
    if (scheduler == null) {
      return null;
    }

    final lock = _agentActionSchedulerInstanceLock;

    return <String, Object?>{
      'started': scheduler.isTemporalSchedulerStarted,
      'bootstrap_disabled': scheduler.isBootstrapDisabled,
      'temporal_timer_count': scheduler.scheduledTimerCount,
      if (lock != null) 'instance_lock_held': lock.isHeld,
      if (scheduler.lastStartIssueReason case final String reason) 'last_start_issue_reason': reason,
    };
  }

  Map<String, Object?>? _buildAgentActionRetentionHealth() {
    final settings = _agentActionRetentionSettings;
    if (settings == null) {
      return null;
    }

    return <String, Object?>{
      'execution_days': settings.executionRetentionDays,
      'remote_audit_days': settings.remoteAuditRetentionDays,
      'captured_output_hours': settings.capturedOutputRetentionHours,
      'persisted_override': settings.hasPersistedOverrides,
      'rpc_idempotency_ttl_seconds': settings.agentActionRpcIdempotencyTtl.inSeconds,
    };
  }

  List<String> _agentActionSupportedTypeNames() {
    final registry = _agentActionRunnerRegistry;
    if (registry == null) {
      return const <String>['commandLine'];
    }
    final names = registry.supportedTypes.map((AgentActionType type) => type.name).toList(growable: false);
    return names.isEmpty ? const <String>['commandLine'] : names;
  }

  static int _metricInt(Map<String, Object?> metrics, String key) {
    final value = metrics[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
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
      'direct_limiter_active_count': diagnostics['direct_limiter_active_count'],
      'direct_limiter_max_concurrent': diagnostics['direct_limiter_max_concurrent'],
      'direct_limiter_saturated': diagnostics['direct_limiter_saturated'] ?? false,
      'from_db_responses_total': metrics['rpc_sql_execute_streaming_from_db_response'] ?? 0,
      'auto_from_db_responses_total': metrics['rpc_sql_execute_auto_streaming_from_db_response'] ?? 0,
      'prefer_from_db_responses_total': metrics['rpc_sql_execute_prefer_db_streaming_response'] ?? 0,
      'allowlist_from_db_responses_total': metrics['rpc_sql_execute_allowlist_db_streaming_response'] ?? 0,
      'from_db_skip_total': metrics['rpc_sql_execute_db_streaming_skip'] ?? 0,
      'from_db_skip_reasons': metrics['rpc_sql_execute_db_streaming_skip_reasons'] ?? const <String, int>{},
      'chunked_materialized_responses_total': metrics['rpc_sql_execute_streaming_chunks_response'] ?? 0,
      'materialized_responses_total': metrics['rpc_sql_execute_materialized_response'] ?? 0,
      'cancel_requests_total': metrics['stream_cancel_request'] ?? 0,
      'backpressure_cancels_total': metrics['stream_cancel_backpressure'] ?? 0,
    };
  }

  Map<String, Object?> _buildDirectConnectionHealth(Map<String, Object?> metrics) {
    final limiter = _directConnectionLimiter;
    final poolSize = _odbcSettings?.poolSize;

    return {
      'active_count': limiter?.activeCount ?? metrics['direct_connection_active_count'] ?? 0,
      'max_concurrent': limiter?.maxConcurrent,
      'effective_cap':
          limiter?.maxConcurrent ??
          (poolSize != null ? ConnectionConstants.directOdbcConnectionConcurrency(poolSize) : null),
      'override_requested': ConnectionConstants.directOdbcConnectionMaxConcurrentOverride,
      'override_exceeds_pool': ConnectionConstants.directOdbcConnectionOverrideExceedsPool(poolSize),
      'capacity_strategy': ConnectionConstants.directOdbcConnectionCapacityStrategy(),
      'pool_size_reference': poolSize,
      'is_saturated': limiter?.isSaturated ?? false,
      'opened_total': limiter?.openedTotal ?? metrics['direct_connection_opened'] ?? 0,
      'closed_total': limiter?.closedTotal ?? metrics['direct_connection_closed'] ?? 0,
      'acquire_timeouts_total': metrics['direct_connection_acquire_timeout'] ?? 0,
      'wait_avg_ms': metrics['direct_connection_wait_avg_time_ms'] ?? 0.0,
      'wait_p95_ms': metrics['direct_connection_wait_p95_time_ms'] ?? 0,
      'wait_p99_ms': metrics['direct_connection_wait_p99_time_ms'] ?? 0,
      'wait_sample_count': metrics['direct_connection_wait_sample_count'] ?? 0,
    };
  }

  Future<String?> _loadDriverType() async {
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
