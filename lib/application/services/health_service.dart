import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/health/agent_actions_health_section_builder.dart';
import 'package:plug_agente/application/services/health/direct_connection_health_section_builder.dart';
import 'package:plug_agente/application/services/health/global_storage_health_section_builder.dart';
import 'package:plug_agente/application/services/health/health_status_deriver.dart';
import 'package:plug_agente/application/services/health/pool_health_resolver.dart';
import 'package:plug_agente/application/services/health/pool_health_section_builder.dart';
import 'package:plug_agente/application/services/health/query_metrics_health_section_builder.dart';
import 'package:plug_agente/application/services/health/secure_storage_health_section_builder.dart';
import 'package:plug_agente/application/services/health/sql_queue_health_section_builder.dart';
import 'package:plug_agente/application/services/health/streaming_health_section_builder.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_direct_connection_limiter_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_global_storage_health_snapshot_builder.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_credential_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_pool_discard_inflight_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';

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
    IPoolDiscardInflightDiagnostics? poolDiscardDiagnostics,
    FeatureFlags? featureFlags,
    OdbcRuntimeTuning? odbcRuntimeTuning,
    AgentRuntimeIdentity? agentRuntimeIdentity,
    AgentActionLocalRunnerRegistry? agentActionRunnerRegistry,
    AgentActionRuntimeStateGuard? agentActionRuntimeStateGuard,
    ElevatedActionRunnerReadinessService? elevatedRunnerReadiness,
    AgentActionRetentionSettings? agentActionRetentionSettings,
    AgentActionTriggerScheduler? agentActionTriggerScheduler,
    IAgentActionSchedulerInstanceLock? agentActionSchedulerInstanceLock,
    IGlobalStorageHealthSnapshotBuilder? globalStorageHealthSnapshotBuilder,
    GlobalStorageContext? globalStorageContext,
    IComObjectInvocationDiagnostics? comObjectInvocationDiagnostics,
    IOdbcCredentialSecretStore? odbcCredentialSecretStore,
    IHubAuthSecretStore? hubAuthSecretStore,
    ITokenSecretStore? tokenSecretStore,
    Duration poolSnapshotTtl = const Duration(seconds: 2),
  }) : _metrics = metricsCollector,
       _gateway = gateway,
       _odbcRuntimeTuning = odbcRuntimeTuning,
       _agentRuntimeIdentity = agentRuntimeIdentity,
       _poolDiscardDiagnostics = poolDiscardDiagnostics,
       _poolResolver = PoolHealthResolver(
         connectionPool: connectionPool,
         activeConfigResolver: activeConfigResolver,
         configRepository: configRepository,
         poolSnapshotTtl: poolSnapshotTtl,
       ),
       _poolSectionBuilder = PoolHealthSectionBuilder(odbcSettings: odbcSettings),
       _sqlQueueSectionBuilder = const SqlQueueHealthSectionBuilder(),
       _streamingSectionBuilder = StreamingHealthSectionBuilder(
         streamingGateway: streamingGateway,
         featureFlags: featureFlags,
       ),
       _directConnectionSectionBuilder = DirectConnectionHealthSectionBuilder(
         directConnectionLimiter: directConnectionLimiter,
         odbcSettings: odbcSettings,
       ),
       _secureStorageSectionBuilder = SecureStorageHealthSectionBuilder(
         odbcCredentialSecretStore: odbcCredentialSecretStore,
         hubAuthSecretStore: hubAuthSecretStore,
         tokenSecretStore: tokenSecretStore,
       ),
       _agentActionsSectionBuilder = AgentActionsHealthSectionBuilder(
         featureFlags: featureFlags,
         agentActionRunnerRegistry: agentActionRunnerRegistry,
         agentActionRuntimeStateGuard: agentActionRuntimeStateGuard,
         elevatedRunnerReadiness: elevatedRunnerReadiness,
         agentActionRetentionSettings: agentActionRetentionSettings,
         agentActionTriggerScheduler: agentActionTriggerScheduler,
         agentActionSchedulerInstanceLock: agentActionSchedulerInstanceLock,
         globalStorageContext: globalStorageContext,
         comObjectInvocationDiagnostics: comObjectInvocationDiagnostics,
       ),
       _globalStorageSectionBuilder = GlobalStorageHealthSectionBuilder(
         globalStorageHealthSnapshotBuilder: globalStorageHealthSnapshotBuilder,
         globalStorageContext: globalStorageContext,
       ),
       _queryMetricsSectionBuilder = const QueryMetricsHealthSectionBuilder();

  final IMetricsCollector _metrics;
  final IDatabaseGateway _gateway;
  final OdbcRuntimeTuning? _odbcRuntimeTuning;
  final AgentRuntimeIdentity? _agentRuntimeIdentity;
  final IPoolDiscardInflightDiagnostics? _poolDiscardDiagnostics;
  final PoolHealthResolver _poolResolver;
  final PoolHealthSectionBuilder _poolSectionBuilder;
  final SqlQueueHealthSectionBuilder _sqlQueueSectionBuilder;
  final StreamingHealthSectionBuilder _streamingSectionBuilder;
  final DirectConnectionHealthSectionBuilder _directConnectionSectionBuilder;
  final SecureStorageHealthSectionBuilder _secureStorageSectionBuilder;
  final AgentActionsHealthSectionBuilder _agentActionsSectionBuilder;
  final GlobalStorageHealthSectionBuilder _globalStorageSectionBuilder;
  final QueryMetricsHealthSectionBuilder _queryMetricsSectionBuilder;

  /// Gets current health status with system metrics.
  Map<String, Object?> getHealthStatus() {
    return _buildHealthStatus();
  }

  /// Gets current health status with async pool diagnostics when available.
  Future<Map<String, Object?>> getHealthStatusAsync() async {
    await _poolResolver.reconcilePoolDiscardInflight(_poolDiscardDiagnostics);
    final poolSnapshot = await _poolResolver.resolvePoolSnapshot();
    final poolDiagnostics = poolSnapshot.diagnostics;
    final driverType = await _poolResolver.resolveDriverType(poolDiagnostics: poolDiagnostics);

    return _buildHealthStatus(
      poolActiveCount: _poolResolver.connectionPool == null ? null : poolSnapshot.activeCount,
      poolDiagnostics: poolDiagnostics,
      driverType: driverType,
    );
  }

  Map<String, Object?> _buildHealthStatus({
    int? poolActiveCount,
    Map<String, Object?> poolDiagnostics = const <String, Object?>{},
    String? driverType,
  }) {
    final metrics = _metrics.getSnapshot();
    final queuedGateway = _gateway is QueuedDatabaseGateway ? _gateway : null;
    final identity = _agentRuntimeIdentity;
    final secureStorage = _secureStorageSectionBuilder.build();
    final status = deriveHealthOverallStatus(
      poolDiagnostics: poolDiagnostics,
      queuedGateway: queuedGateway,
      secureStorage: secureStorage,
    );

    return {
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
      'version': AppConstants.appVersion,
      if (identity != null)
        'agent_runtime': <String, Object?>{
          'instance_id': identity.runtimeInstanceId,
          'session_id': identity.runtimeSessionId,
        },
      'odbc_runtime_tuning': _odbcRuntimeTuning?.toMap(),
      'pool': _poolSectionBuilder.build(
        metrics: metrics,
        poolDiagnostics: poolDiagnostics,
        poolActiveCount: poolActiveCount,
        driverType: driverType,
      ),
      'streaming': _streamingSectionBuilder.build(metrics),
      'direct_connections': _directConnectionSectionBuilder.build(metrics),
      'sql_queue': _sqlQueueSectionBuilder.build(
        queuedGateway: queuedGateway,
        metrics: metrics,
      ),
      'prepared': _queryMetricsSectionBuilder.buildPrepared(metrics),
      'timeouts': _queryMetricsSectionBuilder.buildTimeouts(metrics),
      'queries': _queryMetricsSectionBuilder.buildQueries(metrics),
      'sql_execution_by_mode': metrics['sql_execution_by_mode'] ?? const <String, Object>{},
      'batch': _queryMetricsSectionBuilder.buildBatch(metrics),
      'diagnostics': _queryMetricsSectionBuilder.buildDiagnostics(metrics),
      if (_agentActionsSectionBuilder.build(metrics) case final Map<String, Object?> agentActions)
        'agent_actions': agentActions,
      if (_globalStorageSectionBuilder.build() case final Map<String, Object?> globalStorage)
        'global_storage': globalStorage,
      if (secureStorage case final Map<String, Object?> storage) 'secure_storage': storage,
      'uptime_seconds': AppUptime.uptimeSeconds,
    };
  }

  /// Gets detailed metrics for monitoring/debugging.
  Map<String, Object?> getDetailedMetrics() {
    return _metrics.getSnapshot();
  }
}
