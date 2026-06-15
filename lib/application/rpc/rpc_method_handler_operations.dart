import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/agent_metadata_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/factories/default_rpc_method_handler_operations_factory.dart';
import 'package:plug_agente/application/rpc/rpc_idempotency_coordinator.dart';
import 'package:plug_agente/application/rpc/sql_rpc_method_handler_operations.dart';
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
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_diagnostics_snapshot_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_sql_in_flight_execution_abort_port.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:uuid/uuid.dart';

class DefaultRpcMethodHandlerOperations {
  factory DefaultRpcMethodHandlerOperations({
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
    Duration sqlExecuteTotalBudget = _defaultSqlExecuteTotalBudget,
    Duration sqlBatchTotalBudget = _defaultSqlBatchTotalBudget,
    Duration authorizationStageBudget = _defaultAuthorizationStageBudget,
    Duration queryStageBudget = _defaultQueryStageBudget,
    Duration batchExecutionStageBudget = _defaultBatchExecutionStageBudget,
    SqlStreamingCoordinator? sqlStreamingCoordinator,
    RpcIdempotencyCoordinator? idempotencyCoordinator,
    IOdbcConnectionSettings? odbcConnectionSettings,
    ISqlInFlightExecutionAbortPort? inFlightAbortPort,
    DefaultRpcMethodHandlerOperationsFactory? operationsFactory,
  }) {
    final factory = operationsFactory ?? const DefaultRpcMethodHandlerOperationsFactory();
    return factory.create(
      databaseGateway: databaseGateway,
      healthService: healthService,
      normalizerService: normalizerService,
      uuid: uuid,
      authorizeSqlOperation: authorizeSqlOperation,
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: getPolicyRateLimiter,
      featureFlags: featureFlags,
      activeConfigResolver: activeConfigResolver,
      configRepository: configRepository,
      idempotencyStore: idempotencyStore,
      authMetrics: authMetrics,
      deprecationMetrics: deprecationMetrics,
      dispatchMetrics: dispatchMetrics,
      onIdempotencyFingerprintMismatch: onIdempotencyFingerprintMismatch,
      onAgentActionRemoteAuditExecutionCorrelated: onAgentActionRemoteAuditExecutionCorrelated,
      onAgentActionRemoteRateLimited: onAgentActionRemoteRateLimited,
      sqlInvestigation: sqlInvestigation,
      streamingGateway: streamingGateway,
      odbcNativeMetricsService: odbcNativeMetricsService,
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
      agentActionRetentionSettings: agentActionRetentionSettings,
      sqlExecuteTotalBudget: sqlExecuteTotalBudget,
      sqlBatchTotalBudget: sqlBatchTotalBudget,
      authorizationStageBudget: authorizationStageBudget,
      queryStageBudget: queryStageBudget,
      batchExecutionStageBudget: batchExecutionStageBudget,
      sqlStreamingCoordinator: sqlStreamingCoordinator,
      idempotencyCoordinator: idempotencyCoordinator,
      odbcConnectionSettings: odbcConnectionSettings,
      inFlightAbortPort: inFlightAbortPort,
    );
  }

  const DefaultRpcMethodHandlerOperations.assemble({
    required SqlRpcMethodHandlerOperations sqlOperations,
    required AgentActionRpcMethodHandlerOperations agentActionOperations,
    required AgentMetadataRpcMethodHandlerOperations metadataOperations,
  }) : _sqlOperations = sqlOperations,
       _agentActionOperations = agentActionOperations,
       _metadataOperations = metadataOperations;

  final SqlRpcMethodHandlerOperations _sqlOperations;
  final AgentActionRpcMethodHandlerOperations _agentActionOperations;
  final AgentMetadataRpcMethodHandlerOperations _metadataOperations;

  SqlStreamingCoordinator get sqlStreamingCoordinator => _sqlOperations.sqlStreamingCoordinator;

  static const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);
  static const _defaultSqlBatchTotalBudget = Duration(seconds: 45);
  static const _defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const _defaultQueryStageBudget = Duration(seconds: 30);
  static const _defaultBatchExecutionStageBudget = Duration(seconds: 35);

  Future<RpcResponse> handleSqlExecute(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    IRpcStreamEmitter? streamEmitter,
  }) => _sqlOperations.handleSqlExecute(
    request,
    agentId,
    clientToken,
    limits: limits,
    negotiatedExtensions: negotiatedExtensions,
    streamEmitter: streamEmitter,
  );

  Future<RpcResponse> handleSqlExecuteBatch(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
  }) => _sqlOperations.handleSqlExecuteBatch(
    request,
    agentId,
    clientToken,
    limits: limits,
    negotiatedExtensions: negotiatedExtensions,
  );

  Future<RpcResponse> handleSqlBulkInsert(
    RpcRequest request,
    String? clientToken, {
    required TransportLimits limits,
  }) => _sqlOperations.handleSqlBulkInsert(
    request,
    clientToken,
    limits: limits,
  );

  Future<RpcResponse> handleSqlCancel(RpcRequest request) => _sqlOperations.handleSqlCancel(request);

  Future<RpcResponse> handleAgentActionRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _agentActionOperations.handleAgentActionRun(request, agentId, clientToken);

  Future<RpcResponse> handleAgentActionValidateRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _agentActionOperations.handleAgentActionValidateRun(request, agentId, clientToken);

  Future<RpcResponse> handleAgentActionCancel(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _agentActionOperations.handleAgentActionCancel(request, agentId, clientToken);

  Future<RpcResponse> handleAgentActionGetExecution(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _agentActionOperations.handleAgentActionGetExecution(request, agentId, clientToken);

  Future<RpcResponse> handleAgentGetProfile(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _metadataOperations.handleAgentGetProfile(request, agentId, clientToken);

  Future<RpcResponse> handleAgentGetHealth(
    RpcRequest request,
    String? clientToken,
  ) => _metadataOperations.handleAgentGetHealth(request, clientToken);

  Future<RpcResponse> handleClientTokenGetPolicy(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) => _metadataOperations.handleClientTokenGetPolicy(request, agentId, clientToken);
}
