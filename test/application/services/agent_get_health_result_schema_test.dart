import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockAgentActionTriggerScheduler extends Mock implements AgentActionTriggerScheduler {}

class _MockAgentActionSchedulerInstanceLock extends Mock implements IAgentActionSchedulerInstanceLock {}

void main() {
  group('agent.getHealth result schema', () {
    late TransportSchemaLoader loader;
    late JsonSchemaContractValidator validator;

    setUpAll(() async {
      loader = TransportSchemaLoader();
      await loader.loadAll();
      validator = JsonSchemaContractValidator(loader: loader);
    });

    test('should validate health snapshot with agent_actions blocks against published schema', () {
      if (!validator.isLoaded(TransportSchemaIds.resultAgentGetHealth)) {
        return;
      }

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final retention = AgentActionRetentionSettings(InMemoryAppSettingsStore());
      final scheduler = _MockAgentActionTriggerScheduler();
      when(() => scheduler.isTemporalSchedulerStarted).thenReturn(true);
      when(() => scheduler.isBootstrapDisabled).thenReturn(false);
      when(() => scheduler.scheduledTimerCount).thenReturn(2);
      final lock = _MockAgentActionSchedulerInstanceLock();
      when(() => lock.isHeld).thenReturn(true);
      final guard = AgentActionRuntimeStateGuard()..markDegraded(unavailableActionTypes: {AgentActionType.comObject});

      final service = HealthService(
        metricsCollector: MetricsCollector()
          ..recordTerminalOutcome(AgentActionExecutionStatus.succeeded)
          ..recordRpcAgentActionRemoteOutcome(AgentActionRpcConstants.agentActionRunRpcMethodName, success: true)
          ..recordRpcAgentActionBatchReadLimitRejected(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentActionRetentionSettings: retention,
        agentActionTriggerScheduler: scheduler,
        agentActionSchedulerInstanceLock: lock,
        agentActionRuntimeStateGuard: guard,
        elevatedRunnerReadiness: ElevatedActionRunnerReadinessService(),
      );

      final agentActions = service.getHealthStatus()['agent_actions'] as Map<String, Object?>?;
      expect(agentActions, isNotNull);
      final remoteRpc = agentActions!['remote_rpc_counters'] as Map<String, Object?>?;
      expect(remoteRpc?['batch_read_limit_rejected_total'], 1);
      expect(agentActions['retention'], isA<Map<String, Object?>>());
      final schedulerBlock = agentActions['scheduler'] as Map<String, Object?>?;
      expect(schedulerBlock, isNotNull);
      expect(schedulerBlock!['instance_lock_held'], isTrue);

      // Validate agent_actions inside a minimal health shell aligned to required schema fields.
      final minimalHealth = <String, Object?>{
        'status': 'healthy',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'version': AppConstants.appVersion,
        'pool': <String, Object?>{'size': 1},
        'sql_queue': <String, Object?>{'enabled': false},
        'queries': <String, Object?>{
          'total': 0,
          'errors': 0,
          'success_rate': 100,
          'avg_latency_ms': 0,
          'p95_latency_ms': 0,
          'p99_latency_ms': 0,
        },
        'uptime_seconds': 1,
        'agent_actions': agentActions,
      };

      final validation = validator.validate(
        schemaId: TransportSchemaIds.resultAgentGetHealth,
        payload: minimalHealth,
      );

      expect(
        validation.isSuccess(),
        isTrue,
        reason: validation.exceptionOrNull()?.toString() ?? 'schema validation failed',
      );
    });

    test(
      'should validate minimal health when scheduler did not start and exposes last_start_issue_reason',
      () {
        if (!validator.isLoaded(TransportSchemaIds.resultAgentGetHealth)) {
          return;
        }

        final flags = FeatureFlags(InMemoryAppSettingsStore());
        final retention = AgentActionRetentionSettings(InMemoryAppSettingsStore());
        final scheduler = _MockAgentActionTriggerScheduler();
        when(() => scheduler.isTemporalSchedulerStarted).thenReturn(false);
        when(() => scheduler.isBootstrapDisabled).thenReturn(false);
        when(() => scheduler.scheduledTimerCount).thenReturn(0);
        when(() => scheduler.lastStartIssueReason).thenReturn(
          AgentActionTriggerConstants.schedulerInstanceLockedReason,
        );
        final lock = _MockAgentActionSchedulerInstanceLock();
        when(() => lock.isHeld).thenReturn(false);

        final service = HealthService(
          metricsCollector: MetricsCollector(),
          gateway: _MockDatabaseGateway(),
          featureFlags: flags,
          agentActionRetentionSettings: retention,
          agentActionTriggerScheduler: scheduler,
          agentActionSchedulerInstanceLock: lock,
        );

        final agentActions = service.getHealthStatus()['agent_actions'] as Map<String, Object?>?;
        final schedulerBlock = agentActions?['scheduler'] as Map<String, Object?>?;
        expect(schedulerBlock?['started'], isFalse);
        expect(
          schedulerBlock?['last_start_issue_reason'],
          AgentActionTriggerConstants.schedulerInstanceLockedReason,
        );

        final minimalHealth = <String, Object?>{
          'status': 'healthy',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'version': AppConstants.appVersion,
          'pool': <String, Object?>{'size': 1},
          'sql_queue': <String, Object?>{'enabled': false},
          'queries': <String, Object?>{
            'total': 0,
            'errors': 0,
            'success_rate': 100,
            'avg_latency_ms': 0,
            'p95_latency_ms': 0,
            'p99_latency_ms': 0,
          },
          'uptime_seconds': 1,
          'agent_actions': agentActions,
        };

        final validation = validator.validate(
          schemaId: TransportSchemaIds.resultAgentGetHealth,
          payload: minimalHealth,
        );

        expect(
          validation.isSuccess(),
          isTrue,
          reason: validation.exceptionOrNull()?.toString() ?? 'schema validation failed',
        );
      },
    );

    test('should validate typical HealthService snapshot against published schema', () {
      if (!validator.isLoaded(TransportSchemaIds.resultAgentGetHealth)) {
        return;
      }

      const identity = AgentRuntimeIdentity(
        runtimeInstanceId: 'inst-schema-test',
        runtimeSessionId: 'sess-schema-test',
      );
      final tuning = OdbcRuntimeTuning.forPoolSize(poolSize: 4, processorCount: 8);
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        featureFlags: flags,
        agentRuntimeIdentity: identity,
        odbcRuntimeTuning: tuning,
      );

      final validation = validator.validate(
        schemaId: TransportSchemaIds.resultAgentGetHealth,
        payload: service.getHealthStatus(),
      );

      expect(
        validation.isSuccess(),
        isTrue,
        reason: validation.exceptionOrNull()?.toString() ?? 'schema validation failed',
      );
      final snapshot = service.getHealthStatus();
      final runtime = snapshot['agent_runtime'] as Map<String, Object?>?;
      expect(runtime?['instance_id'], identity.runtimeInstanceId);
      final tuningMap = snapshot['odbc_runtime_tuning'] as Map<String, Object?>?;
      expect(tuningMap?['pool_size'], 4);
    });
  });
}
