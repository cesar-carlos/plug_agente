import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/handlers/rpc_method_handlers.dart';
import 'package:plug_agente/application/rpc/rpc_method_concurrency_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_handler.dart';
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
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:uuid/uuid.dart';

const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);
const _defaultSqlBatchTotalBudget = Duration(seconds: 45);
const _defaultAuthorizationStageBudget = Duration(seconds: 3);
const _defaultQueryStageBudget = Duration(seconds: 30);
const _defaultBatchExecutionStageBudget = Duration(seconds: 35);

/// RPC method facade for routing JSON-RPC requests to registered handlers.
class RpcMethodDispatcher implements IRpcRequestDispatcher {
  RpcMethodDispatcher({
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
    TransportLimits defaultLimits = const TransportLimits(),
    Duration sqlExecuteTotalBudget = _defaultSqlExecuteTotalBudget,
    Duration sqlBatchTotalBudget = _defaultSqlBatchTotalBudget,
    Duration authorizationStageBudget = _defaultAuthorizationStageBudget,
    Duration queryStageBudget = _defaultQueryStageBudget,
    Duration batchExecutionStageBudget = _defaultBatchExecutionStageBudget,
    Iterable<RpcMethodHandler>? handlers,
    Future<Map<String, dynamic>> Function()? loadOpenRpcDocument,
    RpcMethodConcurrencyLimiter? methodConcurrencyLimiter,
    SqlStreamingCoordinator? sqlStreamingCoordinator,
    IOdbcConnectionSettings? odbcConnectionSettings,
  }) : _defaultLimits = defaultLimits,
       _dispatchMetrics = dispatchMetrics,
       _methodConcurrencyLimiter = methodConcurrencyLimiter ?? RpcMethodConcurrencyLimiter.fromEnvironment(),
       _sqlStreamingCoordinator =
           sqlStreamingCoordinator ??
           SqlStreamingCoordinator(
             gateway: streamingGateway,
             metrics: dispatchMetrics,
           ) {
    final operations = DefaultRpcMethodHandlerOperations(
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
      sqlStreamingCoordinator: _sqlStreamingCoordinator,
      odbcConnectionSettings: odbcConnectionSettings,
    );
    _handlersByMethod = _buildHandlerRegistry(
      handlers ??
          createDefaultRpcMethodHandlers(
            operations,
            loadOpenRpcDocument: loadOpenRpcDocument,
          ),
    );
  }

  final TransportLimits _defaultLimits;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final RpcMethodConcurrencyLimiter _methodConcurrencyLimiter;
  final SqlStreamingCoordinator _sqlStreamingCoordinator;
  late final Map<String, RpcMethodHandler> _handlersByMethod;

  @override
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  }) async {
    final handler = _handlersByMethod[request.method];
    if (handler == null) {
      return _methodNotFound(request);
    }
    final concurrency = _methodConcurrencyLimiter.tryAcquire(
      method: request.method,
      agentId: agentId,
      clientToken: clientToken,
    );
    if (!concurrency.acquired) {
      _dispatchMetrics?.recordRpcMethodConcurrencyLimited(request.method);
      return _methodConcurrencyLimited(request, concurrency.limit);
    }
    final lease = concurrency.lease;
    try {
      return await handler.handle(
        request,
        RpcDispatchContext(
          agentId: agentId,
          clientToken: clientToken,
          streamEmitter: streamEmitter,
          limits: limits ?? _defaultLimits,
          negotiatedExtensions: negotiatedExtensions,
        ),
      );
    } finally {
      lease?.release();
    }
  }

  @override
  Future<void> cancelActiveStreamOnDisconnect() {
    return _sqlStreamingCoordinator.cancelActiveStreamOnDisconnect();
  }

  Map<String, RpcMethodHandler> _buildHandlerRegistry(
    Iterable<RpcMethodHandler> handlers,
  ) {
    final registry = <String, RpcMethodHandler>{};
    for (final handler in handlers) {
      final previous = registry[handler.method];
      if (previous != null) {
        throw ArgumentError.value(
          handler.method,
          'handlers',
          'Duplicate RPC method handler registration',
        );
      }
      registry[handler.method] = handler;
    }
    return Map.unmodifiable(registry);
  }

  RpcResponse _methodNotFound(RpcRequest request) {
    const code = RpcErrorCode.methodNotFound;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'RPC method not found: ${request.method}',
          correlationId: request.id?.toString(),
          extra: <String, dynamic>{
            'method': request.method,
          },
        ),
      ),
    );
  }

  RpcResponse _methodConcurrencyLimited(RpcRequest request, int? limit) {
    const code = RpcErrorCode.rateLimited;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'RPC method concurrency limit reached for ${request.method}.',
          correlationId: request.id?.toString(),
          reason: 'method_concurrency_limit',
          extra: <String, dynamic>{
            'method': request.method,
            'scope': 'client',
            ...?(limit == null ? null : <String, dynamic>{'limit': limit}),
          },
        ),
      ),
    );
  }
}
