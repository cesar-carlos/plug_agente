import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_com_object_invocation_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/infrastructure/health/global_storage_health_snapshot_builder.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_marker_store.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockConnectionPoolDiagnostics extends Mock implements IConnectionPool, IConnectionPoolDiagnostics {}

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class _MockStreamingGateway extends Mock implements IStreamingDatabaseGateway, IStreamingGatewayDiagnostics {}

class _MockAgentActionTriggerScheduler extends Mock implements AgentActionTriggerScheduler {}

class _MockAgentActionSchedulerInstanceLock extends Mock implements IAgentActionSchedulerInstanceLock {}

class _MockComObjectInvocationDiagnostics extends Mock implements IComObjectInvocationDiagnostics {}

void main() {
  group('HealthService', () {
    test('should omit agent_actions when feature flags are not wired', () {
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
      );

      final status = service.getHealthStatus();
      expect(status.containsKey('agent_actions'), isFalse);
    });

    test('should expose agent_actions with queue and remote rpc counters when feature flags are wired', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final metrics = MetricsCollector()
        ..recordConcurrencyReject()
        ..recordTerminalOutcome(AgentActionExecutionStatus.succeeded)
        ..recordTerminalOutcome(AgentActionExecutionStatus.skipped)
        ..recordExecutionDuration(const Duration(milliseconds: 250))
        ..recordRemotePermissionDenied()
        ..recordLocalAuthorizationDenied()
        ..recordRemoteRateLimited()
        ..recordRemoteAuditExecutionCorrelated()
        ..recordRpcAgentActionRemoteOutcome(AgentActionRpcConstants.agentActionRunRpcMethodName, success: true)
        ..recordRpcAgentActionNotificationRejected(AgentActionRpcConstants.agentActionCancelRpcMethodName)
        ..recordRpcAgentActionBatchReadLimitRejected();
      final guard = AgentActionRuntimeStateGuard();
      guard.markDegraded(unavailableActionTypes: {AgentActionType.developer});
      final service = HealthService(
        metricsCollector: metrics,
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentActionRuntimeStateGuard: guard,
      );

      final status = service.getHealthStatus();
      final agentActions = status['agent_actions']! as Map<String, Object?>;
      expect(agentActions['enabled'], isTrue);
      expect(agentActions['maintenance_strict_mode'], isFalse);
      expect(agentActions['status'], 'degraded');
      expect(agentActions['unavailable_types'], ['developer']);
      final queueCounters = agentActions['queue_counters']! as Map<String, Object?>;
      expect(queueCounters['concurrency_reject_total'], 1);
      final remoteRpc = agentActions['remote_rpc_counters']! as Map<String, Object?>;
      expect(remoteRpc['run_success_total'], 1);
      expect(remoteRpc['cancel_notification_rejected_total'], 1);
      expect(remoteRpc['batch_read_limit_rejected_total'], 1);
      expect(agentActions['queue_wait_ms'], isA<Map<String, Object?>>());
      final executionCounters = agentActions['execution_counters']! as Map<String, Object?>;
      expect(executionCounters['terminal_succeeded_total'], 1);
      expect(executionCounters['terminal_skipped_total'], 1);
      expect(executionCounters['remote_permission_denied_total'], 1);
      expect(executionCounters['local_authorization_denied_total'], 1);
      expect(executionCounters['remote_rate_limited_total'], 1);
      expect(executionCounters['remote_audit_execution_correlated_total'], 1);
      final executionDuration = agentActions['execution_duration_ms']! as Map<String, Object?>;
      expect(executionDuration['sample_count'], 1);
      expect(executionDuration['avg_time_ms'], 250.0);
    });

    test('should expose maintenance_strict_mode when strict maintenance is enabled', () async {
      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);
      await flags.setEnableAgentActionsMaintenanceMode(true);
      await flags.setEnableAgentActionsMaintenanceStrictMode(true);
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
      );

      final status = service.getHealthStatus();
      final agentActions = status['agent_actions']! as Map<String, Object?>;
      expect(agentActions['maintenance_mode'], isTrue);
      expect(agentActions['maintenance_strict_mode'], isTrue);
    });

    test('should expose scheduler diagnostics in agent_actions when scheduler is wired', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final scheduler = _MockAgentActionTriggerScheduler();
      when(() => scheduler.isTemporalSchedulerStarted).thenReturn(true);
      when(() => scheduler.isBootstrapDisabled).thenReturn(false);
      when(() => scheduler.scheduledTimerCount).thenReturn(3);
      final lock = _MockAgentActionSchedulerInstanceLock();
      when(() => lock.isHeld).thenReturn(true);
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentActionTriggerScheduler: scheduler,
        agentActionSchedulerInstanceLock: lock,
      );

      final status = service.getHealthStatus();
      final agentActions = status['agent_actions']! as Map<String, Object?>;
      final schedulerHealth = agentActions['scheduler']! as Map<String, Object?>;
      expect(schedulerHealth['started'], isTrue);
      expect(schedulerHealth['bootstrap_disabled'], isFalse);
      expect(schedulerHealth['temporal_timer_count'], 3);
      expect(schedulerHealth['instance_lock_held'], isTrue);
    });

    test('should expose global_storage when builder and context are wired', () async {
      final tempDir = await Directory.systemTemp.createTemp('plug_health_storage_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });

      final markerStore = GlobalStorageAclMarkerStore(appVersionReader: () => 'test-version');
      final aclBootstrap = GlobalStorageAclBootstrap(markerStore: markerStore);
      await aclBootstrap.ensureDirectoryAcls(tempDir.path);

      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        globalStorageContext: GlobalStorageContext(appDirectoryPath: tempDir.path),
        globalStorageHealthSnapshotBuilder: GlobalStorageHealthSnapshotBuilder(
          aclBootstrap: aclBootstrap,
          markerStore: markerStore,
        ),
      );

      final globalStorage = service.getHealthStatus()['global_storage']! as Map<String, Object?>;
      expect(globalStorage['app_directory_path'], tempDir.path);
      expect(globalStorage['acl_marker_present'], isA<bool>());
    });

    test('should expose lock_file_path when scheduler reports start issue', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final scheduler = _MockAgentActionTriggerScheduler();
      when(() => scheduler.isTemporalSchedulerStarted).thenReturn(false);
      when(() => scheduler.isBootstrapDisabled).thenReturn(false);
      when(() => scheduler.scheduledTimerCount).thenReturn(0);
      when(() => scheduler.lastStartIssueReason).thenReturn(
        AgentActionTriggerConstants.schedulerStorageAccessDeniedReason,
      );
      const storagePath = r'C:\ProgramData\PlugAgente';
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentActionTriggerScheduler: scheduler,
        globalStorageContext: const GlobalStorageContext(appDirectoryPath: storagePath),
      );

      final schedulerHealth =
          (service.getHealthStatus()['agent_actions']! as Map<String, Object?>)['scheduler']! as Map<String, Object?>;
      expect(schedulerHealth['lock_file_path'], contains('agent_action_scheduler.lock'));
      expect(schedulerHealth['lock_file_path'], contains(storagePath));
    });

    test('should expose last_start_issue_reason when temporal scheduler did not start', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final scheduler = _MockAgentActionTriggerScheduler();
      when(() => scheduler.isTemporalSchedulerStarted).thenReturn(false);
      when(() => scheduler.isBootstrapDisabled).thenReturn(false);
      when(() => scheduler.scheduledTimerCount).thenReturn(0);
      when(() => scheduler.lastStartIssueReason).thenReturn(
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentActionTriggerScheduler: scheduler,
      );

      final agentActions = service.getHealthStatus()['agent_actions']! as Map<String, Object?>;
      final schedulerHealth = agentActions['scheduler']! as Map<String, Object?>;
      expect(schedulerHealth['started'], isFalse);
      expect(
        schedulerHealth['last_start_issue_reason'],
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );
    });

    test('should expose com object invocation readiness in agent_actions', () {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final comDiagnostics = _MockComObjectInvocationDiagnostics();
      when(() => comDiagnostics.registeredHandlerCount).thenReturn(0);
      final serviceWithoutHandlers = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        comObjectInvocationDiagnostics: comDiagnostics,
      );

      final withoutHandlers = serviceWithoutHandlers.getHealthStatus()['agent_actions']! as Map<String, Object?>;
      expect(withoutHandlers['com_object_handlers_registered_count'], 0);
      expect(withoutHandlers['com_object_invocation_ready'], isFalse);

      when(() => comDiagnostics.registeredHandlerCount).thenReturn(2);
      final serviceWithHandlers = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        comObjectInvocationDiagnostics: comDiagnostics,
      );
      final withHandlers = serviceWithHandlers.getHealthStatus()['agent_actions']! as Map<String, Object?>;
      expect(withHandlers['com_object_handlers_registered_count'], 2);
      expect(withHandlers['com_object_invocation_ready'], isTrue);
    });

    test('should expose retention policy in agent_actions when retention settings are wired', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final retention = AgentActionRetentionSettings(InMemoryAppSettingsStore());
      await retention.save(
        executionDays: 14,
        remoteAuditDays: 21,
        capturedOutputHours: 48,
      );
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentActionRetentionSettings: retention,
      );

      final status = service.getHealthStatus();
      final agentActions = status['agent_actions']! as Map<String, Object?>;
      final retentionHealth = agentActions['retention']! as Map<String, Object?>;
      expect(retentionHealth['execution_days'], 14);
      expect(retentionHealth['remote_audit_days'], 21);
      expect(retentionHealth['captured_output_hours'], 48);
      expect(retentionHealth['persisted_override'], isTrue);
      expect(retentionHealth['rpc_idempotency_ttl_seconds'], greaterThan(0));
    });

    test('should expose maintenance flags in agent_actions when feature flags are wired', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      await flags.setEnableAgentActionsMaintenanceStrictMode(true);
      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableRemoteAdHocAgentActions(true);
      await flags.setEnableElevatedAgentActions(true);
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
      );

      final agentActions = service.getHealthStatus()['agent_actions']! as Map<String, Object?>;
      expect(agentActions['enabled'], isTrue);
      expect(agentActions['maintenance_mode'], isTrue);
      expect(agentActions['maintenance_strict_mode'], isTrue);
      expect(agentActions['remote_enabled'], isTrue);
      expect(agentActions['remote_ad_hoc_enabled'], isTrue);
      expect(agentActions['elevated_enabled'], isTrue);
    });

    test('should expose elevated readiness and purge counters in agent_actions', () async {
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService()..markDegraded(reason: 'helper timeout');
      final metrics = MetricsCollector()
        ..recordElevatedBridgeArtifactsPurge(3)
        ..recordCapturedOutputCleared(2);
      final service = HealthService(
        metricsCollector: metrics,
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
      );

      final status = service.getHealthStatus();
      final agentActions = status['agent_actions']! as Map<String, Object?>;
      expect(agentActions['elevated_enabled'], isTrue);
      expect(agentActions['elevated_runner_configured'], isFalse);
      expect(agentActions['elevated_runner_degraded'], isTrue);
      final executionCounters = agentActions['execution_counters']! as Map<String, Object?>;
      expect(executionCounters['elevated_bridge_artifacts_purge_total'], 3);
      expect(executionCounters['captured_output_cleared_total'], 2);
    });

    test('should expose agent_runtime when identity is provided', () {
      const identity = AgentRuntimeIdentity(
        runtimeInstanceId: 'inst-test',
        runtimeSessionId: 'sess-test',
      );
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        agentRuntimeIdentity: identity,
      );

      final status = service.getHealthStatus();
      final runtime = status['agent_runtime']! as Map<String, Object?>;
      expect(runtime['instance_id'], 'inst-test');
      expect(runtime['session_id'], 'sess-test');
    });

    test('should report persisted ODBC pool size and actual queue limits', () async {
      final settings = MockOdbcConnectionSettings(poolSize: 7);
      const tuning = OdbcRuntimeTuning(
        poolSize: 7,
        processorCount: 8,
        asyncWorkerCount: 7,
        asyncMaxPendingRequests: 28,
        asyncBackpressureMode: 'failFast',
      );
      final metrics = MetricsCollector()
        ..recordSqlQueueWorkersEqualPool(workers: 7, poolSize: 7)
        ..recordPoolAcquireTimeout()
        ..recordQueryTimeout()
        ..recordPreparedStatementReuse()
        ..recordPreparedPrepareTime(const Duration(milliseconds: 12))
        ..recordDirectConnectionFallback()
        ..recordOdbcNativePoolFallback()
        ..recordTransactionalBatchDirectPath()
        ..recordTransactionalBatchNativePoolPath()
        ..recordTransactionalBatchNativePoolFallback()
        ..recordBatchBulkInsertRecommended();
      final poolMock = _MockConnectionPool();
      when(poolMock.getActiveCount).thenAnswer((_) => Future.value(const Success(2)));
      final queue = SqlExecutionQueue(
        maxQueueSize: 11,
        maxConcurrentWorkers: 7,
        metricsCollector: metrics,
        defaultEnqueueTimeout: const Duration(seconds: 4),
      );
      final gateway = QueuedDatabaseGateway(
        delegate: _MockDatabaseGateway(),
        queue: queue,
      );
      final service = HealthService(
        metricsCollector: metrics,
        gateway: gateway,
        odbcSettings: settings,
        connectionPool: poolMock,
        odbcRuntimeTuning: tuning,
      );

      final status = await service.getHealthStatusAsync();
      final runtime = status['odbc_runtime_tuning']! as Map<String, Object?>;
      final pool = status['pool']! as Map<String, Object?>;
      final sqlQueue = status['sql_queue']! as Map<String, Object?>;
      final prepared = status['prepared']! as Map<String, Object?>;
      final timeouts = status['timeouts']! as Map<String, Object?>;
      final directConnections = status['direct_connections']! as Map<String, Object?>;
      final streaming = status['streaming']! as Map<String, Object?>;
      final batch = status['batch']! as Map<String, Object?>;

      expect(runtime['pool_size'], 7);
      expect(runtime['async_worker_count'], 7);
      expect(runtime['async_max_pending_requests'], 28);
      expect(pool['size'], 7);
      expect(pool['active_count'], 2);
      expect(pool['acquire_timeout_seconds'], 30);
      expect(pool['native_pool_exposed'], isFalse);
      expect(pool['strategy'], 'lease');
      expect(pool['native_circuit_open'], isFalse);
      expect(pool['native_circuit_failures'], 0);
      expect(pool['lease_active_count'], 0);
      expect(pool['native_active_count'], 0);
      expect(pool['fallbacks_total'], 2);
      expect(sqlQueue['enabled'], isTrue);
      expect(sqlQueue['max_size'], 11);
      expect(sqlQueue['max_workers'], 7);
      expect(sqlQueue['max_non_query_workers'], 3);
      expect(sqlQueue['enqueue_timeout_seconds'], 4);
      expect(sqlQueue['workers_equal_pool_total'], 1);
      expect(sqlQueue['pool_wait_timeouts_total'], 1);
      expect(prepared['reuse_total'], 1);
      expect(prepared['prepare_avg_ms'], 12.0);
      expect(timeouts['sql_total'], 1);
      expect(timeouts['pool_total'], 1);
      expect(directConnections['active_count'], 0);
      expect(directConnections['effective_cap'], 3);
      expect(directConnections['override_requested'], isNull);
      expect(directConnections['override_exceeds_pool'], isFalse);
      expect(streaming['active_streams'], 0);
      expect(batch['transactional_direct_total'], 1);
      expect(batch['transactional_native_pool_total'], 1);
      expect(batch['transactional_native_pool_fallback_total'], 1);
      expect(batch['bulk_insert_recommended_total'], 1);
    });

    test('should cache resolved driver type and prefer pool diagnostics metadata', () async {
      final configRepository = _MockAgentConfigRepository();
      final pool = _MockConnectionPoolDiagnostics();
      when(pool.getActiveCount).thenAnswer((_) async => const Success(1));
      when(pool.getHealthDiagnostics).thenReturn(
        const {
          'strategy': 'adaptive_experimental',
          'effective_strategy': 'native',
          'native_pool_exposed': true,
          'experimental_enabled': true,
          'native_eligible': true,
          'lease_active_count': 1,
          'native_active_count': 3,
        },
      );
      when(configRepository.getCurrentConfigMetadata).thenAnswer(
        (_) async => Success(
          Config(
            id: 'cfg-1',
            driverName: 'SQL Server',
            odbcDriverName: 'ODBC Driver 17 for SQL Server',
            connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=.;DATABASE=db;',
            username: 'sa',
            databaseName: 'db',
            host: 'localhost',
            port: 1433,
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        ),
      );

      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        connectionPool: pool,
        configRepository: configRepository,
      );

      final first = await service.getHealthStatusAsync();
      final second = await service.getHealthStatusAsync();

      final poolHealth = first['pool']! as Map<String, Object?>;
      expect(poolHealth['strategy'], 'adaptive_experimental');
      expect(poolHealth['effective_strategy'], 'native');
      expect(poolHealth['driver_type'], 'sqlServer');
      expect(poolHealth['experimental_enabled'], isTrue);
      expect(poolHealth['native_eligible'], isTrue);
      expect(poolHealth['lease_active_count'], 1);
      expect(poolHealth['native_active_count'], 3);
      expect(second['pool'], equals(first['pool']));
      verify(pool.getActiveCount).called(1);
      verify(pool.getHealthDiagnostics).called(1);
      verify(configRepository.getCurrentConfigMetadata).called(1);
    });

    test('should expose streaming and direct connection diagnostics', () async {
      final metrics = MetricsCollector();
      final directLimiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 2,
        acquireTimeout: const Duration(milliseconds: 50),
        metricsCollector: metrics,
      );
      final streamingGateway = _MockStreamingGateway();
      final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
      await featureFlags.setEnableSocketStreamingChunks(true);
      when(streamingGateway.getStreamingDiagnostics).thenReturn(
        const {
          'enabled': true,
          'active_streams': 2,
          'direct_limiter_active_count': 1,
          'direct_limiter_max_concurrent': 2,
          'direct_limiter_saturated': false,
        },
      );
      when(() => streamingGateway.hasActiveStream).thenReturn(true);
      final lease = (await directLimiter.acquire(operation: 'test')).getOrThrow();
      final service = HealthService(
        metricsCollector: metrics,
        gateway: _MockDatabaseGateway(),
        streamingGateway: streamingGateway,
        directConnectionLimiter: directLimiter,
        featureFlags: featureFlags,
      );

      final status = service.getHealthStatus();

      final streaming = status['streaming']! as Map<String, Object?>;
      final directConnections = status['direct_connections']! as Map<String, Object?>;
      expect(streaming['enabled'], isTrue);
      expect(streaming['gateway_available'], isTrue);
      expect(streaming['db_streaming_flag_enabled'], isTrue);
      expect(streaming['chunk_streaming_flag_enabled'], isTrue);
      expect(streaming['active_streams'], 2);
      expect(streaming['direct_limiter_active_count'], 1);
      expect(streaming['direct_limiter_max_concurrent'], 2);
      expect(streaming['direct_limiter_saturated'], isFalse);
      expect(directConnections['active_count'], 1);
      expect(directConnections['max_concurrent'], 2);
      expect(directConnections['effective_cap'], 2);
      expect(directConnections['override_exceeds_pool'], isFalse);
      expect(directConnections['capacity_strategy'], 'half_pool_reserved');
      expect(directConnections['opened_total'], 1);
      expect(directConnections['wait_avg_ms'], isA<double>());
      expect(directConnections['wait_p95_ms'], isA<int>());
      expect(directConnections['wait_sample_count'], 1);

      lease.release();
    });

    test('should report DB streaming auto policy when socket chunking flag is disabled', () {
      final streamingGateway = _MockStreamingGateway();
      when(streamingGateway.getStreamingDiagnostics).thenReturn(
        const {
          'enabled': true,
          'active_streams': 0,
        },
      );
      // Explicitly disable the chunk streaming flag: the agent now defaults it
      // to true, but this test verifies the *fallback* path where chunking is
      // off and the auto-from-db policy must compensate.
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        streamingGateway: streamingGateway,
        featureFlags: FeatureFlags(
          InMemoryAppSettingsStore(<String, Object>{
            'feature_enable_socket_streaming_chunks': false,
          }),
        ),
      );

      final status = service.getHealthStatus();

      final streaming = status['streaming']! as Map<String, Object?>;
      expect(streaming['enabled'], isTrue);
      expect(streaming['gateway_available'], isTrue);
      expect(streaming['db_streaming_flag_enabled'], isTrue);
      expect(streaming['chunk_streaming_flag_enabled'], isFalse);
      expect(streaming['auto_db_streaming_policy_enabled'], isTrue);
    });

    test('should stay healthy when only historical sql queue saturation counters are elevated', () {
      final metrics = MetricsCollector()
        ..recordQueueSaturation(thresholdPercent: 90, currentSize: 15, maxSize: 16);
      final queue = SqlExecutionQueue(
        maxQueueSize: 16,
        maxConcurrentWorkers: 8,
        metricsCollector: metrics,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: _MockDatabaseGateway(),
        queue: queue,
      );
      final service = HealthService(
        metricsCollector: metrics,
        gateway: gateway,
      );

      final status = service.getHealthStatus();

      expect(status['status'], 'healthy');
      final sqlQueue = status['sql_queue']! as Map<String, Object?>;
      expect(sqlQueue['saturation_90_total'], greaterThan(0));
      expect(sqlQueue['current_size'], lessThan(15));
    });

    test('should report degraded when sql queue is currently at or above 90 percent saturation', () async {
      final metrics = MetricsCollector();
      final queue = SqlExecutionQueue(
        maxQueueSize: 10,
        maxConcurrentWorkers: 2,
        metricsCollector: metrics,
      );
      final gateway = QueuedDatabaseGateway(
        delegate: _MockDatabaseGateway(),
        queue: queue,
      );
      final service = HealthService(
        metricsCollector: metrics,
        gateway: gateway,
      );
      final hold = Completer<void>();

      for (var index = 0; index < 11; index++) {
        unawaited(
          queue.submit<String>(
            () async {
              await hold.future;
              return Success('held-$index');
            },
          ),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      final status = service.getHealthStatus();

      expect(queue.queueSize, greaterThanOrEqualTo(9));
      expect(status['status'], 'degraded');
      final sqlQueue = status['sql_queue']! as Map<String, Object?>;
      expect(sqlQueue['current_size'], greaterThanOrEqualTo(9));

      hold.complete();
    });

    test('should expose recent diagnostic reasons and prepared cache counters', () {
      final metrics = MetricsCollector()
        ..recordPreparedStatementReuse()
        ..recordPreparedStatementCacheMiss()
        ..recordSqlExecutionTime(const Duration(milliseconds: 20), mode: 'pooled')
        ..recordSqlExecutionTime(const Duration(milliseconds: 8), mode: 'native_compatible')
        ..recordReadOnlyBatchParallel(requestedParallelism: 4, effectiveParallelism: 2)
        ..recordRpcSqlExecutePreferDbStreamingResponse()
        ..recordRpcSqlExecuteAllowlistDbStreamingResponse()
        ..recordRpcSqlExecuteDbStreamingSkipped('streaming_chunks_not_negotiated')
        ..recordDiagnosticReason(category: 'pool', reason: 'native_fallback')
        ..recordDiagnosticReason(category: 'pool', reason: 'native_fallback')
        ..recordDiagnosticReason(category: 'timeout', reason: 'query_timeout');
      final service = HealthService(
        metricsCollector: metrics,
        gateway: _MockDatabaseGateway(),
      );

      final status = service.getHealthStatus();

      final prepared = status['prepared']! as Map<String, Object?>;
      expect(prepared['cache_hit_total'], 1);
      expect(prepared['cache_miss_total'], 1);
      final diagnostics = status['diagnostics']! as Map<String, Object?>;
      final topReasons = diagnostics['top_recent_reasons']! as Map<String, int>;
      expect(topReasons['pool:native_fallback'], 2);
      expect(topReasons['timeout:query_timeout'], 1);
      final streaming = status['streaming']! as Map<String, Object?>;
      expect(streaming['prefer_from_db_responses_total'], 1);
      expect(streaming['allowlist_from_db_responses_total'], 1);
      expect(streaming['from_db_skip_total'], 1);
      expect(
        streaming['from_db_skip_reasons'],
        containsPair('streaming_chunks_not_negotiated', 1),
      );
      final byMode = status['sql_execution_by_mode']! as Map<String, Object>;
      expect(byMode.keys, containsAll(['pooled', 'native_compatible']));
      final batch = status['batch']! as Map<String, Object?>;
      expect(batch['read_only_parallel_total'], 1);
      expect(batch['read_only_parallel_capped_total'], 1);
      expect(batch['last_requested_parallelism'], 4);
      expect(batch['last_effective_parallelism'], 2);
      expect(batch['parallel_global_wait_sample_count'], 0);
    });
  });
}
