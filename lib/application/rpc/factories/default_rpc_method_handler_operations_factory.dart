import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/factories/agent_action_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/factories/agent_metadata_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/factories/sql_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/pass_through_streaming_named_parameter_preparer.dart';
import 'package:plug_agente/application/rpc/rpc_idempotency_coordinator.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler_idempotency_orchestrator.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/sql_streaming_coordinator.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_diagnostics_snapshot_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:uuid/uuid.dart';

class DefaultRpcMethodHandlerOperationsFactory {
  const DefaultRpcMethodHandlerOperationsFactory({
    SqlRpcMethodHandlerOperationsFactory sqlFactory = const SqlRpcMethodHandlerOperationsFactory(
      PassThroughStreamingNamedParameterPreparer.instance,
    ),
    AgentActionRpcMethodHandlerOperationsFactory agentActionFactory =
        const AgentActionRpcMethodHandlerOperationsFactory(),
    AgentMetadataRpcMethodHandlerOperationsFactory metadataFactory =
        const AgentMetadataRpcMethodHandlerOperationsFactory(),
  }) : _sqlFactory = sqlFactory,
       _agentActionFactory = agentActionFactory,
       _metadataFactory = metadataFactory;

  final SqlRpcMethodHandlerOperationsFactory _sqlFactory;
  final AgentActionRpcMethodHandlerOperationsFactory _agentActionFactory;
  final AgentMetadataRpcMethodHandlerOperationsFactory _metadataFactory;

  DefaultRpcMethodHandlerOperations create({
    required IDatabaseGateway databaseGateway,
    required HealthService healthService,
    required QueryNormalizerService normalizerService,
    required Uuid uuid,
    required AuthorizeSqlOperation authorizeSqlOperation,
    required GetClientTokenPolicy getClientTokenPolicy,
    required ClientTokenGetPolicyRateLimiter getPolicyRateLimiter,
    required FeatureFlags featureFlags,
    ActiveConfigResolver? activeConfigResolver,
    IAgentConfigRepository? configRepository,
    IIdempotencyStore? idempotencyStore,
    IAuthorizationMetricsCollector? authMetrics,
    IDeprecationMetricsCollector? deprecationMetrics,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    void Function()? onIdempotencyFingerprintMismatch,
    void Function()? onAgentActionRemoteAuditExecutionCorrelated,
    void Function()? onAgentActionRemoteRateLimited,
    ISqlInvestigationCollector? sqlInvestigation,
    IStreamingDatabaseGateway? streamingGateway,
    IOdbcDiagnosticsSnapshotCollector? odbcNativeMetricsService,
    RunAgentActionLocally? runAgentActionLocally,
    RunAgentActionViaRemoteTrigger? runAgentActionViaRemoteTrigger,
    CancelAgentActionExecution? cancelAgentActionExecution,
    GetAgentActionExecution? getAgentActionExecution,
    SliceAgentActionCapturedOutput? sliceAgentActionCapturedOutput,
    GetAgentActionDefinition? getAgentActionDefinition,
    BackfillAgentActionExecutionCorrelation? backfillAgentActionExecutionCorrelation,
    AgentActionRemoteRateLimiter? agentActionRemoteRateLimiter,
    AgentActionRemoteAuthorizationService? agentActionRemoteAuthorization,
    IAgentActionRemoteAuditStore? agentActionRemoteAuditStore,
    AgentActionRuntimeStateGuard? agentActionRuntimeStateGuard,
    AgentRuntimeIdentity? agentRuntimeIdentity,
    AgentActionRetentionSettings? agentActionRetentionSettings,
    Duration sqlExecuteTotalBudget = const Duration(seconds: 35),
    Duration sqlBatchTotalBudget = const Duration(seconds: 45),
    Duration authorizationStageBudget = const Duration(seconds: 3),
    Duration queryStageBudget = const Duration(seconds: 30),
    Duration batchExecutionStageBudget = const Duration(seconds: 35),
    SqlStreamingCoordinator? sqlStreamingCoordinator,
    RpcIdempotencyCoordinator? idempotencyCoordinator,
    IOdbcConnectionSettings? odbcConnectionSettings,
    ISqlInFlightExecutionAbortPort? inFlightAbortPort,
  }) {
    final orchestrator = RpcMethodHandlerIdempotencyOrchestrator(
      authorizeSqlOperation: authorizeSqlOperation,
      featureFlags: featureFlags,
      idempotencyStore: idempotencyStore,
      idempotencyCoordinator: idempotencyCoordinator,
      onIdempotencyFingerprintMismatch: onIdempotencyFingerprintMismatch,
      agentActionRetentionSettings: agentActionRetentionSettings,
      authorizationStageBudget: authorizationStageBudget,
    );

    return DefaultRpcMethodHandlerOperations.assemble(
      sqlOperations: _sqlFactory.create(
        databaseGateway: databaseGateway,
        normalizerService: normalizerService,
        uuid: uuid,
        featureFlags: featureFlags,
        support: orchestrator.buildSqlSupport(),
        activeConfigResolver: activeConfigResolver,
        configRepository: configRepository,
        authMetrics: authMetrics,
        deprecationMetrics: deprecationMetrics,
        dispatchMetrics: dispatchMetrics,
        sqlInvestigation: sqlInvestigation,
        streamingGateway: streamingGateway,
        sqlExecuteTotalBudget: sqlExecuteTotalBudget,
        sqlBatchTotalBudget: sqlBatchTotalBudget,
        queryStageBudget: queryStageBudget,
        batchExecutionStageBudget: batchExecutionStageBudget,
        sqlStreamingCoordinator: sqlStreamingCoordinator,
        odbcConnectionSettings: odbcConnectionSettings,
        inFlightAbortPort: inFlightAbortPort,
      ),
      agentActionOperations: _agentActionFactory.create(
        uuid: uuid,
        featureFlags: featureFlags,
        support: orchestrator.buildAgentActionSupport(),
        idempotencyStore: idempotencyStore,
        dispatchMetrics: dispatchMetrics,
        onAgentActionRemoteAuditExecutionCorrelated: onAgentActionRemoteAuditExecutionCorrelated,
        onAgentActionRemoteRateLimited: onAgentActionRemoteRateLimited,
        runAgentActionLocally: runAgentActionLocally,
        runAgentActionViaRemoteTrigger: runAgentActionViaRemoteTrigger,
        cancelAgentActionExecution: cancelAgentActionExecution,
        getAgentActionExecution: getAgentActionExecution,
        sliceAgentActionCapturedOutput: sliceAgentActionCapturedOutput,
        getAgentActionDefinition: getAgentActionDefinition,
        backfillAgentActionExecutionCorrelation: backfillAgentActionExecutionCorrelation,
        agentActionRemoteRateLimiter: agentActionRemoteRateLimiter,
        agentActionRemoteAuthorization: agentActionRemoteAuthorization,
        agentActionRemoteAuditStore: agentActionRemoteAuditStore,
        agentActionRuntimeStateGuard: agentActionRuntimeStateGuard,
        agentRuntimeIdentity: agentRuntimeIdentity,
      ),
      metadataOperations: _metadataFactory.create(
        healthService: healthService,
        getClientTokenPolicy: getClientTokenPolicy,
        getPolicyRateLimiter: getPolicyRateLimiter,
        featureFlags: featureFlags,
        support: orchestrator.buildMetadataSupport(),
        activeConfigResolver: activeConfigResolver,
        configRepository: configRepository,
        dispatchMetrics: dispatchMetrics,
        odbcNativeMetricsService: odbcNativeMetricsService,
        authorizationStageBudget: authorizationStageBudget,
      ),
    );
  }
}
