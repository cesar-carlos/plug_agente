import 'dart:async';

import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/agent_metadata_rpc_method_handler_operations.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
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
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class DefaultRpcMethodHandlerOperations {
  DefaultRpcMethodHandlerOperations({
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
  }) : _authorizeSqlOperation = authorizeSqlOperation,
       _featureFlags = featureFlags,
       _idempotencyStore = idempotencyStore,
       _idempotencyCoordinator = idempotencyCoordinator ?? RpcIdempotencyCoordinator(),
       _onIdempotencyFingerprintMismatch = onIdempotencyFingerprintMismatch,
       _agentActionRetentionSettings = agentActionRetentionSettings,
       _authorizationStageBudgetDuration = authorizationStageBudget {
    _sqlOperations = SqlRpcMethodHandlerOperations(
      databaseGateway: databaseGateway,
      normalizerService: normalizerService,
      uuid: uuid,
      featureFlags: featureFlags,
      support: SqlRpcMethodHandlerSupport(
        invalidParams: _invalidParams,
        methodNotFound: _methodNotFound,
        executionNotFound: _executionNotFound,
        consumeIdempotentCacheIfAny: _consumeIdempotentCacheIfAny,
        storeIdempotentSuccessIfApplicable: _storeIdempotentSuccessIfApplicable,
        runIdempotentExecution: _runIdempotentExecution,
        buildMissingClientTokenFailure: _buildMissingClientTokenFailure,
        authorizeWithBudget: _authorizeWithBudget,
        effectiveStageTimeout: _effectiveStageTimeout,
      ),
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
    );
    _agentActionOperations = AgentActionRpcMethodHandlerOperations(
      uuid: uuid,
      featureFlags: featureFlags,
      support: AgentActionRpcMethodHandlerSupport(
        invalidParams: _invalidParams,
        internalError: _internalError,
        consumeIdempotentCacheIfAny: _consumeIdempotentCacheIfAny,
        storeIdempotentSuccessIfApplicable: _storeIdempotentSuccessIfApplicable,
        runIdempotentExecution: _runIdempotentExecution,
      ),
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
    );
    _metadataOperations = AgentMetadataRpcMethodHandlerOperations(
      healthService: healthService,
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: getPolicyRateLimiter,
      featureFlags: featureFlags,
      support: AgentMetadataRpcMethodHandlerSupport(
        invalidParams: _invalidParams,
        internalError: _internalError,
        buildMissingClientTokenFailure: _buildMissingClientTokenFailure,
        authorizeWithBudget: _authorizeWithBudget,
      ),
      activeConfigResolver: activeConfigResolver,
      configRepository: configRepository,
      dispatchMetrics: dispatchMetrics,
      odbcNativeMetricsService: odbcNativeMetricsService,
      authorizationStageBudget: authorizationStageBudget,
    );
  }

  final AuthorizeSqlOperation _authorizeSqlOperation;
  final FeatureFlags _featureFlags;
  final IIdempotencyStore? _idempotencyStore;
  final RpcIdempotencyCoordinator _idempotencyCoordinator;
  final void Function()? _onIdempotencyFingerprintMismatch;
  final AgentActionRetentionSettings? _agentActionRetentionSettings;
  final Duration _authorizationStageBudgetDuration;

  late final SqlRpcMethodHandlerOperations _sqlOperations;
  late final AgentActionRpcMethodHandlerOperations _agentActionOperations;
  late final AgentMetadataRpcMethodHandlerOperations _metadataOperations;

  SqlStreamingCoordinator get sqlStreamingCoordinator => _sqlOperations.sqlStreamingCoordinator;

  static const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);
  static const _defaultSqlBatchTotalBudget = Duration(seconds: 45);
  static const _defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const _defaultQueryStageBudget = Duration(seconds: 30);
  static const _defaultBatchExecutionStageBudget = Duration(seconds: 35);

  String _namespacedRpcIdempotencyStoreKey(
    RpcRequest request,
    String idempotencyKey,
  ) => '${request.method}:$idempotencyKey';

  Duration _rpcIdempotencyEntryTtl(RpcRequest request) {
    switch (request.method) {
      case AgentActionRpcConstants.agentActionRunRpcMethodName:
      case AgentActionRpcConstants.agentActionValidateRunRpcMethodName:
        return _agentActionRetentionSettings?.agentActionRpcIdempotencyTtl ??
            ConnectionConstants.agentActionRpcIdempotencyEntryTtl;
      default:
        return ConnectionConstants.rpcIdempotencyEntryTtl;
    }
  }

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

  Future<Result<void>> _authorizeWithBudget({
    required String token,
    required String sql,
    required String? requestDatabase,
    required String? requestId,
    required String method,
    required DateTime? deadline,
  }) async {
    final timeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _authorizationStageBudgetDuration,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': RpcSqlBudgetConstants.authorizationBudgetExhaustedReason,
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization budget exhausted before validation',
          context: context,
        ),
      );
    }

    try {
      if (timeout == null) {
        return _authorizeSqlOperation(
          token: token,
          sql: sql,
          requestDatabase: requestDatabase,
          requestId: requestId,
          method: method,
        );
      }
      return await _authorizeSqlOperation(
        token: token,
        sql: sql,
        requestDatabase: requestDatabase,
        requestId: requestId,
        method: method,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': RpcSqlBudgetConstants.authorizationTimeoutReason,
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization stage timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Duration? _effectiveStageTimeout({
    required DateTime? deadline,
    required Duration stageBudget,
  }) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      return Duration.zero;
    }
    return remaining < stageBudget ? remaining : stageBudget;
  }

  RpcResponse _executionNotFound(RpcRequest request) {
    const code = RpcErrorCode.executionNotFound;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage:
              'No in-flight execution found to cancel. '
              'Execution may have completed or never started.',
          correlationId: request.id?.toString(),
          extra: {'method': 'sql.cancel'},
        ),
      ),
    );
  }

  /// Returns a method not found error.
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
          extra: {
            'method': request.method,
          },
        ),
      ),
    );
  }

  /// Returns an invalid params error.
  RpcResponse _invalidParams(
    RpcRequest request,
    String detail, {
    String? rpcReason,
    Map<String, dynamic> extraFields = const <String, dynamic>{},
  }) {
    const code = RpcErrorCode.invalidParams;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: detail,
          correlationId: request.id?.toString(),
          reason: rpcReason ?? RpcErrorCode.getReason(code),
          extra: <String, dynamic>{
            'detail': detail,
            'method': request.method,
            ...extraFields,
          },
        ),
      ),
    );
  }

  /// Returns an internal server error (-32603).
  ///
  /// Use for server-side conditions the client cannot fix, such as a missing
  /// repository or an unexpected runtime state.
  RpcResponse _internalError(RpcRequest request, String detail) {
    const code = RpcErrorCode.internalError;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: detail,
          correlationId: request.id?.toString(),
          extra: {'detail': detail},
        ),
      ),
    );
  }

  Future<RpcResponse> _runIdempotentExecution({
    required RpcRequest request,
    required String? idempotencyKey,
    required String idempotencyFingerprint,
    required Future<RpcResponse> Function() execute,
  }) async {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty ||
        _idempotencyStore == null) {
      return execute();
    }

    final namespacedKey = _namespacedRpcIdempotencyStoreKey(request, idempotencyKey);
    final response = await _idempotencyCoordinator.runExclusive(
      namespacedKey: namespacedKey,
      action: () async {
        final cached = await _consumeIdempotentCacheIfAny(
          request,
          idempotencyKey,
          idempotencyFingerprint,
        );
        if (cached != null) {
          return cached;
        }
        final executed = await execute();
        final sanitized = RpcWireMap.sanitizeRpcResponse(executed);
        await _storeIdempotentSuccessIfApplicable(
          request: request,
          idempotencyKey: idempotencyKey,
          idempotencyFingerprint: idempotencyFingerprint,
          response: sanitized,
        );
        return sanitized;
      },
    );
    return _idempotencyCoordinator.remapResponseId(response, request.id);
  }

  Future<RpcResponse?> _consumeIdempotentCacheIfAny(
    RpcRequest request,
    String? idempotencyKey,
    String idempotencyFingerprint,
  ) async {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty) {
      return null;
    }
    final store = _idempotencyStore;
    if (store == null) {
      return null;
    }
    final namespacedKey = _namespacedRpcIdempotencyStoreKey(request, idempotencyKey);
    final cachedRecord = await store.getRecord(namespacedKey);
    if (cachedRecord != null &&
        cachedRecord.requestFingerprint != null &&
        cachedRecord.requestFingerprint != idempotencyFingerprint) {
      _onIdempotencyFingerprintMismatch?.call();
      if (request.method.startsWith('agent.action.')) {
        return _invalidParams(
          request,
          'idempotency_key was already used with a different request payload',
          rpcReason: AgentActionRpcConstants.remoteIdempotencyFingerprintMismatchRpcReason,
          extraFields: <String, dynamic>{
            'category': RpcErrorCode.categoryAction,
            'idempotency_key': idempotencyKey,
          },
        );
      }
      return _invalidParams(
        request,
        'idempotency_key was already used with a different request payload',
      );
    }
    final cached = cachedRecord?.response;
    if (cached != null) {
      return RpcResponse(
        jsonrpc: cached.jsonrpc,
        id: request.id,
        result: cached.result,
        error: cached.error,
        apiVersion: cached.apiVersion,
        meta: cached.meta,
      );
    }
    return null;
  }

  Future<void> _storeIdempotentSuccessIfApplicable({
    required RpcRequest request,
    required String? idempotencyKey,
    required String idempotencyFingerprint,
    required RpcResponse response,
  }) async {
    if (request.isNotification ||
        !_featureFlags.enableSocketIdempotency ||
        idempotencyKey == null ||
        idempotencyKey.isEmpty) {
      return;
    }
    final store = _idempotencyStore;
    if (store == null) {
      return;
    }
    final namespacedKey = _namespacedRpcIdempotencyStoreKey(request, idempotencyKey);
    await store.set(
      namespacedKey,
      response,
      _rpcIdempotencyEntryTtl(request),
      requestFingerprint: idempotencyFingerprint,
    );
  }

  domain.ConfigurationFailure _buildMissingClientTokenFailure() {
    return domain.ConfigurationFailure.withContext(
      message: 'Client token is required for authorized SQL operations',
      context: {
        'authentication': true,
        'reason': RpcClientTokenConstants.missingClientTokenReason,
      },
    );
  }
}
