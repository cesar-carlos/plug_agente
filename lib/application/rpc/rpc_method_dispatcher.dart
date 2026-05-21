import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_get_execution_output_options.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/rpc/sql_execute_params_reader.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/execute_sql_batch.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/core/constants/rpc_streaming_constants.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/core/utils/batch_odbc_timeout.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart' show sqlStatementsForClientTokenAuthorization;
import 'package:plug_agente/core/utils/sql_row_truncation.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/domain/utils/json_primitive_coercion.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

enum _DbStreamingAutoReason {
  none,
  prefer,
  sqlLength,
  allowlist,
  sqlSignal,
}

/// RPC method dispatcher for routing JSON-RPC requests to handlers.
class RpcMethodDispatcher {
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
    OdbcNativeMetricsService? odbcNativeMetricsService,
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
  }) : _databaseGateway = databaseGateway,
       _healthService = healthService,
       _normalizerService = normalizerService,
       _uuid = uuid,
       _authorizeSqlOperation = authorizeSqlOperation,
       _getClientTokenPolicy = getClientTokenPolicy,
       _getPolicyRateLimiter = getPolicyRateLimiter,
       _featureFlags = featureFlags,
       _activeConfigResolver = activeConfigResolver,
       _configRepository = configRepository,
       _idempotencyStore = idempotencyStore,
       _authMetrics = authMetrics,
       _deprecationMetrics = deprecationMetrics,
       _dispatchMetrics = dispatchMetrics,
       _onIdempotencyFingerprintMismatch = onIdempotencyFingerprintMismatch,
       _onAgentActionRemoteAuditExecutionCorrelated = onAgentActionRemoteAuditExecutionCorrelated,
       _onAgentActionRemoteRateLimited = onAgentActionRemoteRateLimited,
       _sqlInvestigation = sqlInvestigation,
       _streamingGateway = streamingGateway,
       _odbcNativeMetricsService = odbcNativeMetricsService,
       _runAgentActionLocally = runAgentActionLocally,
       _runAgentActionViaRemoteTrigger = runAgentActionViaRemoteTrigger,
       _cancelAgentActionExecution = cancelAgentActionExecution,
       _getAgentActionExecution = getAgentActionExecution,
       _sliceAgentActionCapturedOutput = sliceAgentActionCapturedOutput,
       _getAgentActionDefinition = getAgentActionDefinition,
       _backfillAgentActionExecutionCorrelation = backfillAgentActionExecutionCorrelation,
       _agentActionRemoteRateLimiter = agentActionRemoteRateLimiter,
       _agentActionRemoteAuthorization = agentActionRemoteAuthorization,
       _agentActionRemoteAuditStore = agentActionRemoteAuditStore,
       _agentActionRuntimeStateGuard = agentActionRuntimeStateGuard,
       _agentRuntimeIdentity = agentRuntimeIdentity,
       _agentActionRetentionSettings = agentActionRetentionSettings,
       _defaultLimits = defaultLimits,
       _sqlExecuteTotalBudgetDuration = sqlExecuteTotalBudget,
       _sqlBatchTotalBudgetDuration = sqlBatchTotalBudget,
       _authorizationStageBudgetDuration = authorizationStageBudget,
       _queryStageBudgetDuration = queryStageBudget,
       _batchExecutionStageBudgetDuration = batchExecutionStageBudget,
       _executeSqlBatch = ExecuteSqlBatch(
         databaseGateway,
         normalizerService,
       );

  final IDatabaseGateway _databaseGateway;
  final HealthService _healthService;
  final QueryNormalizerService _normalizerService;
  final Uuid _uuid;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final GetClientTokenPolicy _getClientTokenPolicy;
  final ClientTokenGetPolicyRateLimiter _getPolicyRateLimiter;
  final FeatureFlags _featureFlags;
  final ActiveConfigResolver? _activeConfigResolver;
  final IAgentConfigRepository? _configRepository;
  final IIdempotencyStore? _idempotencyStore;
  final IAuthorizationMetricsCollector? _authMetrics;
  final IDeprecationMetricsCollector? _deprecationMetrics;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final void Function()? _onIdempotencyFingerprintMismatch;
  final void Function()? _onAgentActionRemoteAuditExecutionCorrelated;
  final void Function()? _onAgentActionRemoteRateLimited;
  final ISqlInvestigationCollector? _sqlInvestigation;
  final IStreamingDatabaseGateway? _streamingGateway;
  final OdbcNativeMetricsService? _odbcNativeMetricsService;
  final RunAgentActionLocally? _runAgentActionLocally;
  final RunAgentActionViaRemoteTrigger? _runAgentActionViaRemoteTrigger;
  final CancelAgentActionExecution? _cancelAgentActionExecution;
  final GetAgentActionExecution? _getAgentActionExecution;
  final SliceAgentActionCapturedOutput? _sliceAgentActionCapturedOutput;
  final GetAgentActionDefinition? _getAgentActionDefinition;
  final BackfillAgentActionExecutionCorrelation? _backfillAgentActionExecutionCorrelation;
  final AgentActionRemoteRateLimiter? _agentActionRemoteRateLimiter;
  final AgentActionRemoteAuthorizationService? _agentActionRemoteAuthorization;
  final IAgentActionRemoteAuditStore? _agentActionRemoteAuditStore;
  final AgentActionRuntimeStateGuard? _agentActionRuntimeStateGuard;
  final AgentRuntimeIdentity? _agentRuntimeIdentity;
  final AgentActionRetentionSettings? _agentActionRetentionSettings;
  final TransportLimits _defaultLimits;
  final Duration _sqlExecuteTotalBudgetDuration;
  final Duration _sqlBatchTotalBudgetDuration;
  final Duration _authorizationStageBudgetDuration;
  final Duration _queryStageBudgetDuration;
  final Duration _batchExecutionStageBudgetDuration;
  DateTime? _odbcDiagnosticsCacheExpiresAt;
  Map<String, dynamic>? _odbcDiagnosticsCache;

  static const _odbcDiagnosticsCacheTtl = Duration(seconds: 10);
  static final RegExp _authorizationSqlWhitespaceCollapse = RegExp(r'\s+');
  static const _defaultSqlExecuteTotalBudget = Duration(seconds: 35);
  static const _defaultSqlBatchTotalBudget = Duration(seconds: 45);
  static const _defaultAuthorizationStageBudget = Duration(seconds: 3);
  static const _defaultQueryStageBudget = Duration(seconds: 30);
  static const _defaultBatchExecutionStageBudget = Duration(seconds: 35);
  static const int _dbStreamingAutoSqlLengthThreshold = 240;
  static const String _dbStreamingAutoTableAllowlistEnv = 'DB_STREAMING_AUTO_TABLE_ALLOWLIST';
  static const Duration _dbStreamingAutoTableAllowlistCacheTtl = Duration(seconds: 10);
  static final RegExp _bulkIdentifierPath = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$');
  static const List<String> _dbStreamingAutoLargeSqlSignals = <String>[
    ' join ',
    ' union ',
    ' group by ',
    ' order by ',
  ];
  static const _agentProfileAuthorizationSql = 'SELECT * FROM agent_profile';
  final ExecuteSqlBatch _executeSqlBatch;
  _ActiveStreamExecution? _activeStreamExecution;
  String? _cachedDbStreamingAutoTableAllowlistRaw;
  Set<String> _cachedDbStreamingAutoTableAllowlist = const <String>{};
  DateTime? _cachedDbStreamingAutoTableAllowlistExpiresAt;

  /// Dispatches an RPC request to the appropriate handler.
  Future<RpcResponse> dispatch(
    RpcRequest request,
    String agentId, {
    String? clientToken,
    IRpcStreamEmitter? streamEmitter,
    TransportLimits? limits,
    Map<String, dynamic> negotiatedExtensions = const {},
  }) async {
    final effectiveLimits = limits ?? _defaultLimits;
    return switch (request.method) {
      'sql.execute' => await _handleSqlExecute(
        request,
        agentId,
        clientToken,
        streamEmitter: streamEmitter,
        limits: effectiveLimits,
        negotiatedExtensions: negotiatedExtensions,
      ),
      'sql.executeBatch' => await _handleSqlExecuteBatch(
        request,
        agentId,
        clientToken,
        limits: effectiveLimits,
        negotiatedExtensions: negotiatedExtensions,
      ),
      'sql.bulkInsert' => await _handleSqlBulkInsert(
        request,
        clientToken,
        limits: effectiveLimits,
      ),
      'sql.cancel' => await _handleSqlCancel(request),
      'agent.getProfile' => await _handleAgentGetProfile(
        request,
        agentId,
        clientToken,
      ),
      'agent.getHealth' => await _handleAgentGetHealth(
        request,
        clientToken,
      ),
      'client_token.getPolicy' => await _handleClientTokenGetPolicy(
        request,
        agentId,
        clientToken,
      ),
      AgentActionRpcConstants.agentActionRunRpcMethodName => await _handleAgentActionRun(
        request,
        agentId,
        clientToken,
      ),
      AgentActionRpcConstants.agentActionValidateRunRpcMethodName => await _handleAgentActionValidateRun(
        request,
        agentId,
        clientToken,
      ),
      AgentActionRpcConstants.agentActionCancelRpcMethodName => await _handleAgentActionCancel(
        request,
        agentId,
        clientToken,
      ),
      AgentActionRpcConstants.agentActionGetExecutionRpcMethodName => await _handleAgentActionGetExecution(
        request,
        agentId,
        clientToken,
      ),
      _ => _methodNotFound(request),
    };
  }

  /// Cancels any active ODBC stream when the socket disconnects.
  ///
  /// Called by the transport client on disconnect to release ODBC resources.
  Future<void> cancelActiveStreamOnDisconnect() async {
    final gateway = _streamingGateway;
    if (gateway == null || !gateway.hasActiveStream) return;
    await gateway.cancelActiveStream(
      reason: StreamingCancelReason.socketDisconnect,
    );
    _activeStreamExecution = null;
  }

  String? _trimmedOptionalRpcString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static final RegExp _w3cTraceParentTraceIdSegment = RegExp(r'^[0-9a-fA-F]{32}$');

  /// Extracts the 32-hex W3C trace id from `traceparent` (`{version}-{trace-id}-{parent-id}-{flags}`).
  String? _traceIdFromW3cTraceParent(String? traceParent) {
    final raw = traceParent?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final segments = raw.split('-');
    if (segments.length < 2) {
      return null;
    }
    final candidate = segments[1].trim();
    if (!_w3cTraceParentTraceIdSegment.hasMatch(candidate)) {
      return null;
    }
    return candidate.toLowerCase();
  }

  String? _trimmedAgentActionRpcCorrelationParam(
    RpcRequest request,
    String paramKey,
  ) {
    final params = request.params;
    if (params is! Map<String, dynamic>) {
      return null;
    }
    return _trimmedOptionalRpcString(params[paramKey] as String?);
  }

  String? _resolvedRemoteAgentActionTraceId(RpcRequest request) {
    final fromParams = _trimmedAgentActionRpcCorrelationParam(
      request,
      AgentActionRpcConstants.agentActionRpcParamTraceId,
    );
    if (fromParams != null) {
      return fromParams;
    }
    final explicit = _trimmedOptionalRpcString(request.meta?.traceId);
    if (explicit != null) {
      return explicit;
    }
    return _traceIdFromW3cTraceParent(request.meta?.traceParent);
  }

  String _resolvedRemoteAgentActionRequestedBy(RpcRequest request) {
    final fromParams = _trimmedAgentActionRpcCorrelationParam(
      request,
      AgentActionRpcConstants.agentActionRpcParamRequestedBy,
    );
    if (fromParams != null) {
      return fromParams;
    }
    return _trimmedOptionalRpcString(request.meta?.requestId) ??
        _trimmedOptionalRpcString(request.meta?.agentId) ??
        _trimmedOptionalRpcString(request.id?.toString()) ??
        'remote';
  }

  String? _resolvedRemoteAgentActionIdempotencyKey(RpcRequest request) {
    return _trimmedAgentActionRpcCorrelationParam(
      request,
      AgentActionRpcConstants.agentActionRpcParamIdempotencyKey,
    );
  }

  Map<String, dynamic> _agentActionParamsForIdempotencyFingerprint(
    Map<String, dynamic> params,
  ) {
    return Map<String, dynamic>.fromEntries(
      params.entries.where(
        (MapEntry<String, dynamic> entry) =>
            !AgentActionRpcConstants.agentActionRpcCorrelationOnlyParamKeys.contains(entry.key),
      ),
    );
  }

  String? _executionIdFromAgentActionRpcSuccessResult(dynamic result) {
    if (result is! Map<String, dynamic>) {
      return null;
    }
    final top = result['execution_id'];
    if (top is String && top.trim().isNotEmpty) {
      return top.trim();
    }
    final nested = result['execution'];
    if (nested is Map<String, dynamic>) {
      final nestedId = nested['execution_id'];
      if (nestedId is String && nestedId.trim().isNotEmpty) {
        return nestedId.trim();
      }
    }
    return null;
  }

  String? _rpcErrorReasonFromData(RpcError error) {
    final data = error.data;
    if (data is Map<String, dynamic>) {
      final reason = data['reason'];
      if (reason is String && reason.trim().isNotEmpty) {
        return reason.trim();
      }
    }
    return null;
  }

  Future<RpcResponse> _finishAgentActionRpcWithAudit({
    required RpcRequest request,
    required String rpcMethod,
    required RpcResponse response,
    required bool credentialPresent,
    String? actionId,
    String? executionId,
    String? idempotencyKey,
    ClientTokenPolicy? resolvedClientTokenPolicy,
  }) async {
    final notificationRejected = request.isNotification &&
        !response.isSuccess &&
        response.error != null &&
        _rpcErrorReasonFromData(response.error!) ==
            AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason;
    if (notificationRejected) {
      _dispatchMetrics?.recordRpcAgentActionNotificationRejected(rpcMethod);
    } else {
      _dispatchMetrics?.recordRpcAgentActionRemoteOutcome(
        rpcMethod,
        success: response.isSuccess,
      );
    }
    final errCode = response.error?.code;
    final reason = response.error != null ? _rpcErrorReasonFromData(response.error!) : null;
    final outcome = _resolveRemoteAuditOutcome(
      response: response,
      notificationRejected: notificationRejected,
      reasonCode: reason,
    );
    final effectiveExecutionId =
        executionId ?? (response.isSuccess ? _executionIdFromAgentActionRpcSuccessResult(response.result) : null);
    await _appendAgentActionRemoteAuditRecord(
      request: request,
      rpcMethod: rpcMethod,
      outcome: outcome,
      credentialPresent: credentialPresent,
      actionId: actionId,
      executionId: effectiveExecutionId,
      idempotencyKey: idempotencyKey ?? _resolvedRemoteAgentActionIdempotencyKey(request),
      reasonCode: reason,
      rpcErrorCode: errCode,
      resolvedClientTokenPolicy: resolvedClientTokenPolicy,
      correlateExecution: true,
    );
    return response;
  }

  String _resolveRemoteAuditOutcome({
    required RpcResponse response,
    required bool notificationRejected,
    required String? reasonCode,
  }) {
    if (response.isSuccess) {
      return AgentActionRemoteAuditConstants.outcomeSuccess;
    }
    if (notificationRejected) {
      return AgentActionRemoteAuditConstants.outcomeNotificationRejected;
    }
    if (reasonCode == AgentActionRpcConstants.agentActionPermissionDeniedErrorReason ||
        reasonCode == RpcClientTokenConstants.missingClientTokenReason ||
        reasonCode == AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason ||
        reasonCode == AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason) {
      return AgentActionRemoteAuditConstants.outcomeAuthorizationDenied;
    }
    if (reasonCode == AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason) {
      return AgentActionRemoteAuditConstants.outcomeRateLimited;
    }
    return AgentActionRemoteAuditConstants.outcomeRpcError;
  }

  Future<void> _appendAgentActionRemoteAuditReceived({
    required RpcRequest request,
    required String rpcMethod,
    required bool credentialPresent,
    String? actionId,
    String? executionId,
    String? idempotencyKey,
    ClientTokenPolicy? resolvedClientTokenPolicy,
  }) async {
    await _appendAgentActionRemoteAuditRecord(
      request: request,
      rpcMethod: rpcMethod,
      outcome: AgentActionRemoteAuditConstants.outcomeReceived,
      credentialPresent: credentialPresent,
      actionId: actionId,
      executionId: executionId,
      idempotencyKey: idempotencyKey ?? _resolvedRemoteAgentActionIdempotencyKey(request),
      resolvedClientTokenPolicy: resolvedClientTokenPolicy,
      correlateExecution: false,
    );
  }

  Future<void> _appendAgentActionRemoteAuditRecord({
    required RpcRequest request,
    required String rpcMethod,
    required String outcome,
    required bool credentialPresent,
    required bool correlateExecution, String? actionId,
    String? executionId,
    String? idempotencyKey,
    String? reasonCode,
    int? rpcErrorCode,
    ClientTokenPolicy? resolvedClientTokenPolicy,
  }) async {
    if (!_featureFlags.enableAgentActionRemoteAudit) {
      return;
    }
    final store = _agentActionRemoteAuditStore;
    if (store == null) {
      return;
    }
    try {
      await store.append(
        AgentActionRemoteAuditRecord(
          id: _uuid.v4(),
          occurredAtUtc: DateTime.now().toUtc(),
          rpcMethod: rpcMethod,
          outcome: outcome,
          credentialPresent: credentialPresent,
          actionId: actionId,
          executionId: executionId,
          traceId: _resolvedRemoteAgentActionTraceId(request),
          requestedBy: _resolvedRemoteAgentActionRequestedBy(request),
          reasonCode: reasonCode,
          rpcErrorCode: rpcErrorCode,
          clientId: AgentActionRemoteAuthorizationService.auditClientId(resolvedClientTokenPolicy),
          tokenJti: AgentActionRemoteAuthorizationService.auditTokenJti(resolvedClientTokenPolicy),
          runtimeInstanceId: _agentRuntimeIdentity?.runtimeInstanceId,
          runtimeSessionId: _agentRuntimeIdentity?.runtimeSessionId,
          idempotencyKey: idempotencyKey ?? _resolvedRemoteAgentActionIdempotencyKey(request),
        ),
      );
      if (correlateExecution) {
        _recordRemoteAuditExecutionCorrelatedIfApplicable(executionId: executionId);
      }
    } on Exception catch (e, stackTrace) {
      final trace = _resolvedRemoteAgentActionTraceId(request);
      developer.log(
        'agent.action remote audit append failed (best effort) '
        'rpcMethod=$rpcMethod actionId=${actionId ?? '-'} '
        'traceId=${trace ?? '-'} idempotencyKey=${idempotencyKey ?? '-'}',
        name: 'rpc_method_dispatcher',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AgentActionExecution> _withRpcCorrelationBackfill(
    AgentActionExecution execution,
    RpcRequest request,
  ) async {
    final backfill = _backfillAgentActionExecutionCorrelation;
    if (backfill == null) {
      return execution;
    }
    final result = await backfill(
      execution: execution,
      traceId: _resolvedRemoteAgentActionTraceId(request),
      requestedBy: _resolvedRemoteAgentActionRequestedBy(request),
    );
    return result.fold(
      (AgentActionExecution updated) => updated,
      (_) => execution,
    );
  }

  void _recordRemoteAuditExecutionCorrelatedIfApplicable({
    required String? executionId,
  }) {
    final trimmedExecutionId = executionId?.trim();
    if (trimmedExecutionId == null || trimmedExecutionId.isEmpty) {
      return;
    }
    final identity = _agentRuntimeIdentity;
    final instanceId = identity?.runtimeInstanceId.trim();
    if (identity == null || instanceId == null || instanceId.isEmpty) {
      return;
    }
    _onAgentActionRemoteAuditExecutionCorrelated?.call();
  }

  /// Namespaces idempotency keys in [IIdempotencyStore] by JSON-RPC method so the
  /// same client key cannot collide across different RPC methods.
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

  Future<String> _resolveAgentActionRpcIdempotencyFingerprint(
    RpcRequest request,
    Map<String, dynamic> params,
  ) async {
    final fingerprintParams = _agentActionParamsForIdempotencyFingerprint(params);
    final identity = _agentRuntimeIdentity;
    if (identity == null) {
      return resolveIdempotencyFingerprint(request.method, fingerprintParams);
    }
    return resolveIdempotencyFingerprint(
      request.method,
      fingerprintParams,
      runtimeInstanceId: identity.runtimeInstanceId,
      runtimeSessionId: identity.runtimeSessionId,
    );
  }

  RpcResponse _agentActionRemoteRateLimitedRpc(RpcRequest request, Duration? retryAfter) {
    const code = RpcErrorCode.rateLimited;
    final retryAfterMs = retryAfter != null && retryAfter > Duration.zero ? retryAfter.inMilliseconds : null;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'Agent action remote rate limit exceeded',
          correlationId: request.id?.toString(),
          reason: AgentActionRpcConstants.agentActionRemoteRateLimitedErrorReason,
          extra: <String, dynamic>{
            'method': request.method,
            'retry_after_ms': ?retryAfterMs,
          },
        ),
      ),
    );
  }

  RpcResponse? _agentActionRpcGateResponse(RpcRequest request) {
    if (!_featureFlags.enableAgentActions) {
      return _agentActionFeatureDisabledResponse(request);
    }
    if (_featureFlags.enableAgentActionsMaintenanceMode) {
      return _agentActionMaintenanceModeResponse(request);
    }
    if (_agentActionRuntimeSubsystemGateResponse(request) case final RpcResponse runtimeGated) {
      return runtimeGated;
    }
    return _agentActionRemoteFeatureDisabledResponse(request);
  }

  /// Fast path for Hub RPC when the local subsystem is not accepting remote work
  /// (starting, draining, maintenance, disabled). Per-type degraded checks remain in
  /// [RunAgentActionLocally] after the action definition is loaded.
  RpcResponse? _agentActionRuntimeSubsystemGateResponse(RpcRequest request) {
    final guard = _agentActionRuntimeStateGuard;
    if (guard == null) {
      return null;
    }

    const remoteProbe = AgentActionExecutionRequest(
      actionId: '_rpc_gate_probe',
      source: AgentActionRequestSource.remoteHub,
      idempotencyKey: '_rpc_gate_probe',
    );
    final gateResult = guard.ensureCanAcceptExecution(
      request: remoteProbe,
      actionType: AgentActionType.commandLine,
    );
    if (gateResult.isSuccess()) {
      return null;
    }

    final failure = gateResult.exceptionOrNull();
    if (failure is! domain.Failure) {
      return null;
    }

    return RpcResponse.error(
      id: request.id,
      error: FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      ),
    );
  }

  String? _trimmedAgentActionRpcStringParam(RpcRequest request, String key) {
    if (request.params is! Map<String, dynamic>) {
      return null;
    }
    final raw = (request.params as Map<String, dynamic>)[key];
    if (raw is! String) {
      return null;
    }
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  RpcResponse _agentActionMaintenanceModeResponse(RpcRequest request) {
    const code = RpcErrorCode.agentActionsTemporarilyUnavailable;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'Agent actions are in maintenance mode',
          correlationId: request.id?.toString(),
          reason: AgentActionRpcConstants.agentActionsMaintenanceModeErrorReason,
          extra: <String, dynamic>{
            'method': request.method,
          },
        ),
      ),
    );
  }

  RpcResponse _agentActionFeatureDisabledResponse(RpcRequest request) {
    const code = RpcErrorCode.agentActionsTemporarilyUnavailable;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'Agent actions are disabled by feature flag',
          correlationId: request.id?.toString(),
          reason: AgentActionRpcConstants.agentActionsFeatureDisabledErrorReason,
          extra: <String, dynamic>{
            'method': request.method,
          },
        ),
      ),
    );
  }

  RpcResponse? _agentActionRemoteFeatureDisabledResponse(RpcRequest request) {
    if (_featureFlags.enableRemoteAgentActions) {
      return null;
    }

    const code = RpcErrorCode.unauthorized;
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'Remote agent actions are disabled by feature flag',
          correlationId: request.id?.toString(),
          reason: AgentActionRpcConstants.agentActionsRemoteDisabledErrorReason,
          extra: <String, dynamic>{
            'method': request.method,
          },
        ),
      ),
    );
  }

  RpcResponse? _tryApplyAgentActionRemoteRateLimit({
    required RpcRequest request,
    required String agentId,
    required String method,
    required String scopeActionId,
    required String? clientToken,
  }) {
    final limiter = _agentActionRemoteRateLimiter;
    if (limiter == null) {
      return null;
    }
    final requesterKey = clientToken != null && clientToken.trim().isNotEmpty
        ? hashClientCredentialToken(clientToken.trim())
        : 'anonymous';
    final decision = limiter.tryAcquire(
      agentId: agentId,
      method: method,
      actionId: scopeActionId,
      requesterKey: requesterKey,
    );
    if (decision.allowed) {
      return null;
    }
    _onAgentActionRemoteRateLimited?.call();
    return _agentActionRemoteRateLimitedRpc(request, decision.retryAfter);
  }

  Future<({RpcResponse? denied, ClientTokenPolicy? policy})> _authorizeAgentActionClientTokenIfNeeded({
    required RpcRequest request,
    required String? clientToken,
    required String authorizationSql,
    required String requiredAgentActionScope,
    required String actionIdForAllowlist,
  }) async {
    final authorization = _agentActionRemoteAuthorization;
    if (authorization == null) {
      return (denied: null, policy: null);
    }
    return authorization.authorizeIfNeeded(
      request: request,
      clientToken: clientToken,
      authorizationSql: authorizationSql,
      requiredAgentActionScope: requiredAgentActionScope,
      actionIdForAllowlist: actionIdForAllowlist,
    );
  }

  Future<ClientTokenPolicy?> _resolveClientTokenPolicyForRemoteAuditRow({
    required String? clientToken,
    ClientTokenPolicy? fromAuthorization,
  }) async {
    final authorization = _agentActionRemoteAuthorization;
    if (authorization == null) {
      return fromAuthorization;
    }
    return authorization.resolvePolicyForAudit(
      clientToken: clientToken,
      fromAuthorization: fromAuthorization,
    );
  }

  Future<RpcResponse> _handleAgentActionRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final runner = _runAgentActionViaRemoteTrigger;
    var actionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (runner == null) {
      response = _internalError(
        request,
        'Remote agent action trigger dispatch is not configured on this dispatcher.',
      );
    } else if (_agentActionRpcGateResponse(request) case final RpcResponse gated) {
      actionId = _trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      response = gated;
    } else {
      actionId = _trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      if (request.isNotification) {
        response = _invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _invalidParams(request, 'params must be an object');
      } else if (actionId.isEmpty) {
        response = _invalidParams(request, 'params.action_id is required');
      } else {
        final params = request.params as Map<String, dynamic>;
        final idempotencyKey = (params['idempotency_key'] as String?)?.trim() ?? '';
        final auth = await _authorizeAgentActionClientTokenIfNeeded(
          request: request,
          clientToken: clientToken,
          authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionRun,
          requiredAgentActionScope: AgentActionRpcConstants.agentActionsRunScope,
          actionIdForAllowlist: actionId,
        );
        tokenPolicyForAudit = auth.policy;
        if (auth.denied != null) {
          response = auth.denied!;
        } else {
          final rateLimited = _tryApplyAgentActionRemoteRateLimit(
            request: request,
            agentId: agentId,
            method: request.method,
            scopeActionId: actionId,
            clientToken: clientToken,
          );
          if (rateLimited != null) {
            response = rateLimited;
          } else {
            final traceId = _resolvedRemoteAgentActionTraceId(request);
            final requestedBy = _resolvedRemoteAgentActionRequestedBy(request);
            String? idempotencyKeyForCache;
            var idempotencyFingerprint = '';
            RpcResponse? idempotentEarly;
            if (idempotencyKey.isNotEmpty && _featureFlags.enableSocketIdempotency && _idempotencyStore != null) {
              idempotencyKeyForCache = idempotencyKey;
              idempotencyFingerprint = await _resolveAgentActionRpcIdempotencyFingerprint(request, params);
              idempotentEarly = await _consumeIdempotentCacheIfAny(
                request,
                idempotencyKeyForCache,
                idempotencyFingerprint,
              );
            }
            if (idempotentEarly != null) {
              response = idempotentEarly;
            } else {
              final triggerId = _trimmedAgentActionRpcStringParam(
                request,
                AgentActionRpcConstants.agentActionRpcParamTriggerId,
              );
              final result = await runner(
                actionId: actionId,
                idempotencyKey: idempotencyKey,
                triggerId: triggerId,
                requestedBy: requestedBy,
                traceId: traceId,
              );
              response = await result.fold<Future<RpcResponse>>(
                (AgentActionExecution execution) async {
                  final rpcResponse = RpcResponse.success(
                    id: request.id,
                    result: agentActionExecutionToGetExecutionResult(
                      execution,
                      sanitizeForRemoteHub: true,
                    ),
                  );
                  if (idempotencyKeyForCache != null && idempotencyFingerprint.isNotEmpty) {
                    await _storeIdempotentSuccessIfApplicable(
                      request: request,
                      idempotencyKey: idempotencyKeyForCache,
                      idempotencyFingerprint: idempotencyFingerprint,
                      response: rpcResponse,
                    );
                  }
                  return rpcResponse;
                },
                (Exception failure) async => RpcResponse.error(
                  id: request.id,
                  error: FailureToRpcErrorMapper.map(
                    failure as domain.Failure,
                    instance: request.id?.toString(),
                    useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                  ),
                ),
              );
            }
          }
        }
      }
    }

    final policyForAudit = await _resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
      actionId: actionId.isEmpty ? null : actionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<RpcResponse> _handleAgentActionValidateRun(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final runner = _runAgentActionLocally;
    var actionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (runner == null) {
      response = _internalError(request, 'Agent action execution is not configured on this dispatcher.');
    } else if (_agentActionRpcGateResponse(request) case final RpcResponse gated) {
      actionId = _trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      response = gated;
    } else {
      actionId = _trimmedAgentActionRpcStringParam(request, 'action_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
        credentialPresent: hadCredential,
        actionId: actionId.isEmpty ? null : actionId,
      );
      if (request.isNotification) {
        response = _invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _invalidParams(request, 'params must be an object');
      } else if (actionId.isEmpty) {
        response = _invalidParams(request, 'params.action_id is required');
      } else {
        final params = request.params as Map<String, dynamic>;
        final idempotencyKey = (params['idempotency_key'] as String?)?.trim() ?? '';
        final auth = await _authorizeAgentActionClientTokenIfNeeded(
          request: request,
          clientToken: clientToken,
          authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionValidateRun,
          requiredAgentActionScope: AgentActionRpcConstants.agentActionsValidateRunScope,
          actionIdForAllowlist: actionId,
        );
        tokenPolicyForAudit = auth.policy;
        if (auth.denied != null) {
          response = auth.denied!;
        } else {
          final rateLimited = _tryApplyAgentActionRemoteRateLimit(
            request: request,
            agentId: agentId,
            method: request.method,
            scopeActionId: actionId,
            clientToken: clientToken,
          );
          if (rateLimited != null) {
            response = rateLimited;
          } else {
            final traceId = _resolvedRemoteAgentActionTraceId(request);
            final requestedBy = _resolvedRemoteAgentActionRequestedBy(request);
            String? idempotencyKeyForCache;
            var idempotencyFingerprint = '';
            RpcResponse? idempotentEarly;
            if (idempotencyKey.isNotEmpty && _featureFlags.enableSocketIdempotency && _idempotencyStore != null) {
              idempotencyKeyForCache = idempotencyKey;
              idempotencyFingerprint = await _resolveAgentActionRpcIdempotencyFingerprint(request, params);
              idempotentEarly = await _consumeIdempotentCacheIfAny(
                request,
                idempotencyKeyForCache,
                idempotencyFingerprint,
              );
            }
            if (idempotentEarly != null) {
              response = idempotentEarly;
            } else {
              final result = await runner.validateRemoteRun(
                AgentActionExecutionRequest(
                  actionId: actionId,
                  source: AgentActionRequestSource.remoteHub,
                  idempotencyKey: idempotencyKey,
                  requestedBy: requestedBy,
                  traceId: traceId,
                ),
              );
              response = await result.fold<Future<RpcResponse>>(
                (AgentActionValidateRunSummary summary) async {
                  final rpcResponse = RpcResponse.success(
                    id: request.id,
                    result: summary.toRpcResultJson(),
                  );
                  if (idempotencyKeyForCache != null && idempotencyFingerprint.isNotEmpty) {
                    await _storeIdempotentSuccessIfApplicable(
                      request: request,
                      idempotencyKey: idempotencyKeyForCache,
                      idempotencyFingerprint: idempotencyFingerprint,
                      response: rpcResponse,
                    );
                  }
                  return rpcResponse;
                },
                (Exception failure) async => RpcResponse.error(
                  id: request.id,
                  error: FailureToRpcErrorMapper.map(
                    failure as domain.Failure,
                    instance: request.id?.toString(),
                    useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                  ),
                ),
              );
            }
          }
        }
      }
    }

    final policyForAudit = await _resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
      actionId: actionId.isEmpty ? null : actionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<RpcResponse> _handleAgentActionCancel(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final cancel = _cancelAgentActionExecution;
    var executionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (cancel == null) {
      response = _internalError(request, 'Agent action cancel is not configured on this dispatcher.');
    } else if (_agentActionRpcGateResponse(request) case final RpcResponse gated) {
      executionId = _trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      response = gated;
    } else {
      executionId = _trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      if (request.isNotification) {
        response = _invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _invalidParams(request, 'params must be an object');
      } else if (executionId.isEmpty) {
        response = _invalidParams(request, 'params.execution_id is required');
      } else {
        final trimmedCredential = clientToken?.trim();
        final needsAgentActionPolicyContext =
            _featureFlags.enableClientTokenAuthorization && trimmedCredential != null && trimmedCredential.isNotEmpty;
        RpcResponse? prefetchFailureResponse;
        var executionActionIdForPolicy = '';
        if (needsAgentActionPolicyContext) {
          final lookup = _getAgentActionExecution;
          if (lookup == null) {
            prefetchFailureResponse = _internalError(
              request,
              'Agent action execution lookup is not configured on this dispatcher.',
            );
          } else {
            final prefetchResult = await lookup(executionId);
            prefetchResult.fold(
              (AgentActionExecution execution) => executionActionIdForPolicy = execution.actionId,
              (Exception failure) => prefetchFailureResponse = RpcResponse.error(
                id: request.id,
                error: FailureToRpcErrorMapper.map(
                  failure as domain.Failure,
                  instance: request.id?.toString(),
                  useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                ),
              ),
            );
          }
        }
        if (prefetchFailureResponse != null) {
          response = prefetchFailureResponse!;
        } else {
          final auth = await _authorizeAgentActionClientTokenIfNeeded(
            request: request,
            clientToken: clientToken,
            authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionCancel,
            requiredAgentActionScope: AgentActionRpcConstants.agentActionsCancelScope,
            actionIdForAllowlist: executionActionIdForPolicy,
          );
          tokenPolicyForAudit = auth.policy;
          if (auth.denied != null) {
            response = auth.denied!;
          } else {
            final rateLimited = _tryApplyAgentActionRemoteRateLimit(
              request: request,
              agentId: agentId,
              method: request.method,
              scopeActionId: executionId,
              clientToken: clientToken,
            );
            if (rateLimited != null) {
              response = rateLimited;
            } else {
              final result = await cancel(executionId);
              response = await result.fold(
                (AgentActionExecution execution) async {
                  final correlated = await _withRpcCorrelationBackfill(execution, request);
                  return RpcResponse.success(
                    id: request.id,
                    result: agentActionCancelToRpcResult(correlated, cancelled: true),
                  );
                },
                (Exception failure) async => RpcResponse.error(
                  id: request.id,
                  error: FailureToRpcErrorMapper.map(
                    failure as domain.Failure,
                    instance: request.id?.toString(),
                    useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                  ),
                ),
              );
            }
          }
        }
      }
    }

    final policyForAudit = await _resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
      executionId: executionId.isEmpty ? null : executionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<Map<String, dynamic>> _agentActionGetExecutionRpcResult({
    required AgentActionExecution execution,
    required Map<String, dynamic> params,
  }) async {
    final outputOptions = await _resolveAgentActionGetExecutionOutputOptions(
      params: params,
      execution: execution,
    );
    CapturedOutputUtf8Window? stdoutWindow;
    CapturedOutputUtf8Window? stderrWindow;
    final slice = _sliceAgentActionCapturedOutput;
    if (slice != null) {
      if (execution.stdoutStoredInChunks && outputOptions.exposeStdout) {
        final sliceResult = await slice(
          executionId: execution.id,
          stream: AgentActionCapturedOutputConstants.stdoutStream,
          offsetUtf8: outputOptions.paging.stdoutOffsetUtf8,
          maxBytes: outputOptions.paging.maxOutputBytesPerStream,
        );
        stdoutWindow = sliceResult.getOrNull();
      }
      if (execution.stderrStoredInChunks && outputOptions.exposeStderr) {
        final sliceResult = await slice(
          executionId: execution.id,
          stream: AgentActionCapturedOutputConstants.stderrStream,
          offsetUtf8: outputOptions.paging.stderrOffsetUtf8,
          maxBytes: outputOptions.paging.maxOutputBytesPerStream,
        );
        stderrWindow = sliceResult.getOrNull();
      }
    }

    return agentActionExecutionToGetExecutionResult(
      execution,
      paging: outputOptions.paging,
      exposeStdout: outputOptions.exposeStdout,
      exposeStderr: outputOptions.exposeStderr,
      sanitizeForRemoteHub: true,
      stdoutWindow: stdoutWindow,
      stderrWindow: stderrWindow,
    );
  }

  Future<RpcResponse> _handleAgentActionGetExecution(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    final hadCredential = clientToken != null && clientToken.trim().isNotEmpty;
    final getExecution = _getAgentActionExecution;
    var executionId = '';
    ClientTokenPolicy? tokenPolicyForAudit;
    late final RpcResponse response;
    if (getExecution == null) {
      response = _internalError(request, 'Agent action execution lookup is not configured on this dispatcher.');
    } else if (_agentActionRpcGateResponse(request) case final RpcResponse gated) {
      executionId = _trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      response = gated;
    } else {
      executionId = _trimmedAgentActionRpcStringParam(request, 'execution_id') ?? '';
      await _appendAgentActionRemoteAuditReceived(
        request: request,
        rpcMethod: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
        credentialPresent: hadCredential,
        executionId: executionId.isEmpty ? null : executionId,
      );
      if (request.isNotification) {
        response = _invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _invalidParams(request, 'params must be an object');
      } else if (executionId.isEmpty) {
        response = _invalidParams(request, 'params.execution_id is required');
      } else {
        final params = request.params as Map<String, dynamic>;
        final trimmedCredential = clientToken?.trim();
        final needsAgentActionPolicyContext =
            _featureFlags.enableClientTokenAuthorization && trimmedCredential != null && trimmedCredential.isNotEmpty;
        RpcResponse? prefetchFailureResponse;
        AgentActionExecution? cachedExecution;
        if (needsAgentActionPolicyContext) {
          final prefetchResult = await getExecution(
            executionId,
            hydrateCapturedOutput: false,
          );
          prefetchResult.fold(
            (AgentActionExecution execution) => cachedExecution = execution,
            (Exception failure) => prefetchFailureResponse = RpcResponse.error(
              id: request.id,
              error: FailureToRpcErrorMapper.map(
                failure as domain.Failure,
                instance: request.id?.toString(),
                useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
              ),
            ),
          );
        }
        if (prefetchFailureResponse != null) {
          response = prefetchFailureResponse!;
        } else {
          final auth = await _authorizeAgentActionClientTokenIfNeeded(
            request: request,
            clientToken: clientToken,
            authorizationSql: AgentActionRpcConstants.clientTokenAuthorizationSqlAgentActionGetExecution,
            requiredAgentActionScope: AgentActionRpcConstants.agentActionsReadExecutionScope,
            actionIdForAllowlist: cachedExecution?.actionId ?? '',
          );
          tokenPolicyForAudit = auth.policy;
          if (auth.denied != null) {
            response = auth.denied!;
          } else {
            final rateLimited = _tryApplyAgentActionRemoteRateLimit(
              request: request,
              agentId: agentId,
              method: request.method,
              scopeActionId: executionId,
              clientToken: clientToken,
            );
            if (rateLimited != null) {
              response = rateLimited;
            } else {
              final cached = cachedExecution;
              if (cached != null) {
                final correlated = await _withRpcCorrelationBackfill(cached, request);
                response = RpcResponse.success(
                  id: request.id,
                  result: await _agentActionGetExecutionRpcResult(
                    execution: correlated,
                    params: params,
                  ),
                );
              } else {
                final result = await getExecution(
                  executionId,
                  hydrateCapturedOutput: false,
                );
                response = await result.fold(
                  (AgentActionExecution execution) async {
                    final correlated = await _withRpcCorrelationBackfill(execution, request);
                    return RpcResponse.success(
                      id: request.id,
                      result: await _agentActionGetExecutionRpcResult(
                        execution: correlated,
                        params: params,
                      ),
                    );
                  },
                  (Exception failure) async => RpcResponse.error(
                    id: request.id,
                    error: FailureToRpcErrorMapper.map(
                      failure as domain.Failure,
                      instance: request.id?.toString(),
                      useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                    ),
                  ),
                );
              }
            }
          }
        }
      }
    }

    final policyForAudit = await _resolveClientTokenPolicyForRemoteAuditRow(
      clientToken: clientToken,
      fromAuthorization: tokenPolicyForAudit,
    );
    return _finishAgentActionRpcWithAudit(
      request: request,
      rpcMethod: AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
      executionId: executionId.isEmpty ? null : executionId,
      response: response,
      credentialPresent: hadCredential,
      resolvedClientTokenPolicy: policyForAudit,
    );
  }

  Future<AgentActionGetExecutionOutputOptions> _resolveAgentActionGetExecutionOutputOptions({
    required Map<String, dynamic> params,
    required AgentActionExecution execution,
  }) async {
    AgentActionCapturePolicy? capturePolicy;
    final getDefinition = _getAgentActionDefinition;
    if (getDefinition != null) {
      final definitionResult = await getDefinition(execution.actionId);
      if (definitionResult.isSuccess()) {
        capturePolicy = definitionResult.getOrThrow().policies.capture;
      }
    }

    return resolveAgentActionGetExecutionOutputOptions(
      params: params,
      capturePolicy: capturePolicy,
    );
  }

  /// Handles sql.execute method (single command).
  Future<RpcResponse> _handleSqlExecute(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
    IRpcStreamEmitter? streamEmitter,
  }) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final paramReader = SqlExecuteParamsReader(params);
    final sql = paramReader.sql;
    final maxRows = _resolveMaxRows(params, limits.maxRows);
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_sqlExecuteTotalBudgetDuration)
        : null;

    if (sql == null || sql.isEmpty) {
      return _invalidParams(request, 'sql is required');
    }
    final options = paramReader.options;
    if (options?['preserve_sql'] == true) {
      _deprecationMetrics?.recordPreserveSqlUsage(
        requestId: request.id?.toString(),
        method: request.method,
      );
    }
    final sqlHandlingModeResolution = _resolveSqlHandlingMode(params);
    if (sqlHandlingModeResolution.hasError) {
      return _invalidParams(
        request,
        sqlHandlingModeResolution.errorMessage!,
      );
    }
    final sqlHandlingMode = sqlHandlingModeResolution.sqlHandlingMode!;
    final paginationResolution = sqlHandlingMode == SqlHandlingMode.preserve
        ? const _ResolvedPagination()
        : _resolvePagination(
            params,
            sql,
            maxRows,
            negotiatedExtensions,
          );
    if (paginationResolution.hasError) {
      return _invalidParams(request, paginationResolution.errorMessage!);
    }
    final pagination = paginationResolution.pagination;
    final multiResultRequested = _resolveMultiResult(params);
    final requestParameters = paramReader.boundParams;
    final database = paramReader.database;
    final requestedTimeoutMs = _resolveRequestedTimeoutMs(params);

    if (multiResultRequested && requestParameters != null && requestParameters.isNotEmpty) {
      return _invalidParams(
        request,
        'multi_result is not supported with named parameters',
      );
    }
    if (multiResultRequested && pagination != null) {
      return _invalidParams(
        request,
        'multi_result cannot be combined with pagination',
      );
    }

    final idempotencyKey = paramReader.idempotencyKey;
    final idempotencyFingerprint = await resolveIdempotencyFingerprint(
      request.method,
      params,
    );
    final idempotentEarly = await _consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint,
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      _authMetrics?.recordDenied(
        requestId: request.id?.toString(),
        method: request.method,
        reason: RpcClientTokenConstants.missingClientTokenReason,
      );
      _recordAuthSqlDenied(
        request,
        sql: sql,
        explicitReason: RpcClientTokenConstants.missingClientTokenReason,
      );
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authDenied = await _authorizeSqlExecuteWithClientToken(
        request: request,
        sql: sql,
        multiResultRequested: multiResultRequested,
        clientToken: clientToken,
        requestDatabase: database,
        deadline: deadline,
      );
      if (authDenied != null) {
        return authDenied;
      }
    }

    // Validate SQL (allows SELECT, WITH, UPDATE, INSERT, MERGE, DELETE)
    final validation = SqlValidator.validateSqlForExecution(
      sql,
      allowMultipleStatements: multiResultRequested,
    );
    if (validation.isError()) {
      final failure = validation.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final queryRequest = QueryRequest(
      id: _uuid.v4(),
      agentId: agentId,
      query: sql,
      parameters: requestParameters,
      timestamp: DateTime.now(),
      pagination: pagination,
      expectMultipleResults: multiResultRequested,
      sqlHandlingMode: sqlHandlingMode,
      sourceRpcRequestId: request.id?.toString(),
    );

    final streamingFromDbResponse = await _tryStreamingFromDb(
      request,
      queryRequest,
      sql,
      request.isNotification ? null : streamEmitter,
      limits: limits,
      deadline: deadline,
      timeoutMs: requestedTimeoutMs,
      negotiatedExtensions: negotiatedExtensions,
      preferDbStreaming: options?['prefer_db_streaming'] == true,
    );
    if (streamingFromDbResponse != null) {
      return streamingFromDbResponse;
    }

    final result = await _executeQueryWithBudget(
      queryRequest,
      database: database,
      requestId: request.id?.toString(),
      deadline: deadline,
      timeoutMs: requestedTimeoutMs,
    );

    return result.fold<Future<RpcResponse>>(
      (QueryResponse queryResponse) async {
        // Normalize
        var normalized = _normalizerService.normalize(queryResponse);

        var multiResultSetsTruncated = false;
        if (normalized.resultSets.isNotEmpty) {
          final beforeMulti = normalized;
          normalized = _applyMaxRowsToMultiResultSets(normalized, maxRows);
          multiResultSetsTruncated = _multiResultSetsWereTruncated(
            beforeMulti,
            normalized,
          );
        }

        final limitedRows = normalized.resultSets.isNotEmpty
            ? normalized.data
            : truncateSqlResultRows(normalized.data, maxRows);
        final wasTruncated =
            multiResultSetsTruncated ||
            (!normalized.resultSets.isNotEmpty && limitedRows.length != normalized.data.length);
        final useStreaming =
            _featureFlags.enableSocketStreamingChunks &&
            streamEmitter != null &&
            !request.isNotification &&
            pagination == null &&
            !normalized.hasMultiResult &&
            limitedRows.length > limits.streamingRowThreshold;

        if (useStreaming) {
          final streamId = 'stream-${queryRequest.id}';
          final rows = limitedRows;
          final totalChunks = (rows.length / limits.streamingChunkSize).ceil();
          var overflowed = false;

          for (var i = 0; i < rows.length && !overflowed; i += limits.streamingChunkSize) {
            final chunkEnd = i + limits.streamingChunkSize > rows.length ? rows.length : i + limits.streamingChunkSize;
            final chunkRows = rows.sublist(i, chunkEnd);
            if (!await streamEmitter.emitChunk(
              RpcStreamChunk(
                streamId: streamId,
                requestId: request.id,
                chunkIndex: i ~/ limits.streamingChunkSize,
                rows: chunkRows,
                totalChunks: totalChunks,
                columnMetadata: normalized.columnMetadata,
              ),
            )) {
              overflowed = true;
              break;
            }
          }

          if (!overflowed) {
            _dispatchMetrics?.recordSqlExecuteStreamingChunksResponse();
          }

          if (overflowed) {
            await _emitTerminalComplete(
              streamEmitter: streamEmitter,
              streamId: streamId,
              requestId: request.id,
              totalRows: rows.length,
              status: StreamTerminalStatus.aborted,
            );
            return RpcResponse.error(
              id: request.id,
              error: RpcError(
                code: RpcErrorCode.resultTooLarge,
                message: RpcErrorCode.getMessage(RpcErrorCode.resultTooLarge),
                data: RpcErrorCode.buildErrorData(
                  code: RpcErrorCode.resultTooLarge,
                  technicalMessage:
                      'Streaming buffer overflowed: hub not consuming fast enough; '
                      'stream cancelled to avoid data loss.',
                  correlationId: request.id?.toString(),
                  subreason: RpcStreamingConstants.backpressureOverflowReason,
                ),
              ),
            );
          }

          await streamEmitter.emitComplete(
            RpcStreamComplete(
              streamId: streamId,
              requestId: request.id,
              totalRows: rows.length,
              affectedRows: normalized.affectedRows,
              executionId: normalized.id,
              startedAt: queryRequest.timestamp.toIso8601String(),
              finishedAt: normalized.timestamp.toIso8601String(),
            ),
          );

          final resultData = {
            'stream_id': streamId,
            'execution_id': normalized.id,
            'started_at': queryRequest.timestamp.toIso8601String(),
            'finished_at': normalized.timestamp.toIso8601String(),
            'sql_handling_mode': queryRequest.sqlHandlingMode.name,
            'max_rows_handling': 'response_truncation',
            'effective_max_rows': maxRows,
            'rows': <Map<String, dynamic>>[],
            'row_count': 0,
            'affected_rows': normalized.affectedRows,
            'returned_rows': rows.length,
            if (wasTruncated) 'truncated': true,
            if (normalized.columnMetadata != null) 'column_metadata': normalized.columnMetadata,
            if (normalized.pagination != null) 'pagination': _buildPaginationResult(normalized.pagination!),
          };

          return RpcResponse.success(id: request.id, result: resultData);
        }

        final resultData = _buildExecuteResultData(
          normalized,
          startedAt: queryRequest.timestamp,
          finishedAt: normalized.timestamp,
          limitedRows: limitedRows,
          wasTruncated: wasTruncated,
          sqlHandlingMode: queryRequest.sqlHandlingMode,
          effectiveMaxRows: maxRows,
          forceMultiResultEnvelope: multiResultRequested,
        );

        final rpcResponse = RpcResponse.success(
          id: request.id,
          result: resultData,
        );
        _dispatchMetrics?.recordSqlExecuteMaterializedResponse();
        await _storeIdempotentSuccessIfApplicable(
          request: request,
          idempotencyKey: idempotencyKey,
          idempotencyFingerprint: idempotencyFingerprint,
          response: rpcResponse,
        );
        return rpcResponse;
      },
      (Exception failure) async {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  /// Tries to stream directly from DB when enabled. Returns null to fall back.
  Future<RpcResponse?> _tryStreamingFromDb(
    RpcRequest request,
    QueryRequest queryRequest,
    String sql,
    IRpcStreamEmitter? streamEmitter, {
    required TransportLimits limits,
    required DateTime? deadline,
    required int timeoutMs,
    required Map<String, dynamic> negotiatedExtensions,
    required bool preferDbStreaming,
  }) async {
    final autoStreamingReason = _dbStreamingAutoReason(
      queryRequest: queryRequest,
      sql: sql,
      negotiatedExtensions: negotiatedExtensions,
      preferDbStreaming: preferDbStreaming,
    );
    final autoStreaming = autoStreamingReason != _DbStreamingAutoReason.none;
    if (!_supportsStreamingChunks(negotiatedExtensions)) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('streaming_chunks_not_negotiated');
      return null;
    }
    if (!_featureFlags.enableSocketStreamingFromDb ||
        (!_featureFlags.enableSocketStreamingChunks && !autoStreaming) ||
        streamEmitter == null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('feature_or_emitter_unavailable');
      return null;
    }
    if (queryRequest.pagination != null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('paginated_request');
      return null;
    }
    if (queryRequest.expectMultipleResults) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('multi_result_request');
      return null;
    }
    final configResolver = _activeConfigResolver;
    final legacyRepository = _configRepository;
    final gateway = _streamingGateway;
    if ((configResolver == null && legacyRepository == null) || gateway == null) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('gateway_unavailable');
      return null;
    }
    final streamingDiagnostics = gateway is IStreamingGatewayDiagnostics
        ? gateway as IStreamingGatewayDiagnostics
        : null;
    if (!_featureFlags.enableSocketStreamingChunks &&
        autoStreamingReason == _DbStreamingAutoReason.prefer &&
        streamingDiagnostics?.getStreamingDiagnostics()['direct_limiter_saturated'] == true) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('direct_limiter_saturated_prefer_fallback');
      return null;
    }
    if (queryRequest.parameters?.isNotEmpty ?? false) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('bound_parameters');
      return null;
    }
    if (SqlValidator.validateSelectQuery(sql).isError()) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('non_select_sql');
      return null;
    }

    final configResult = configResolver != null
        ? await configResolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await legacyRepository!.getCurrentConfigMetadata();
    final config = configResult.getOrNull();
    if (config == null || config.resolveConnectionString().trim().isEmpty) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('config_unavailable');
      return null;
    }
    if (!_isDbStreamingDriverAllowed(config.driverName)) {
      _dispatchMetrics?.recordSqlExecuteDbStreamingSkipped('driver_not_allowed');
      return null;
    }

    final streamId = 'stream-${queryRequest.id}';
    final executionId = _uuid.v4();
    var totalRows = 0;
    var chunkIndex = 0;
    var overflowed = false;
    List<Map<String, dynamic>>? columnMetadata;
    _activeStreamExecution = _ActiveStreamExecution(
      streamId: streamId,
      requestId: request.id?.toString(),
      executionId: executionId,
    );

    try {
      final queryTimeout = mergeOdbcTimeout(
        stageTimeout: _effectiveStageTimeout(
          deadline: deadline,
          stageBudget: _sqlExecuteTotalBudgetDuration,
        ),
        timeoutMs: timeoutMs,
      );
      final streamResult = await gateway.executeQueryStream(
        sql.trim(),
        config.resolveConnectionString(),
        (chunk) async {
          if (columnMetadata == null && chunk.isNotEmpty) {
            columnMetadata = chunk.first.keys.map((k) => <String, dynamic>{'name': k, 'type': 'string'}).toList();
          }
          totalRows += chunk.length;
          if (!await streamEmitter.emitChunk(
            RpcStreamChunk(
              streamId: streamId,
              requestId: request.id,
              chunkIndex: chunkIndex++,
              rows: chunk,
              columnMetadata: columnMetadata,
            ),
          )) {
            overflowed = true;
            await gateway.cancelActiveStream(
              executionId: executionId,
              reason: StreamingCancelReason.backpressureOverflow,
            );
          }
        },
        fetchSize: limits.streamingChunkSize,
        executionId: executionId,
        queryTimeout: queryTimeout,
      );

      if (streamResult.isError()) {
        final failure = streamResult.exceptionOrNull()! as domain.Failure;
        final isBackpressure = failure.context['reason'] == RpcStreamingConstants.backpressureOverflowReason;
        await _emitTerminalComplete(
          streamEmitter: streamEmitter,
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          status: isBackpressure ? StreamTerminalStatus.aborted : StreamTerminalStatus.error,
        );
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }

      if (overflowed) {
        await _emitTerminalComplete(
          streamEmitter: streamEmitter,
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          status: StreamTerminalStatus.aborted,
        );
        return RpcResponse.error(
          id: request.id,
          error: RpcError(
            code: RpcErrorCode.resultTooLarge,
            message: RpcErrorCode.getMessage(RpcErrorCode.resultTooLarge),
            data: RpcErrorCode.buildErrorData(
              code: RpcErrorCode.resultTooLarge,
              technicalMessage:
                  'Streaming buffer overflowed: hub not consuming fast enough; '
                  'stream cancelled to avoid data loss.',
              correlationId: request.id?.toString(),
              subreason: RpcStreamingConstants.backpressureOverflowReason,
            ),
          ),
        );
      }

      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: request.id,
          totalRows: totalRows,
          affectedRows: totalRows,
          executionId: executionId,
          startedAt: queryRequest.timestamp.toIso8601String(),
          finishedAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      final dbStreamResponse = RpcResponse.success(
        id: request.id,
        result: {
          'stream_id': streamId,
          'execution_id': executionId,
          'started_at': queryRequest.timestamp.toIso8601String(),
          'finished_at': DateTime.now().toUtc().toIso8601String(),
          'sql_handling_mode': queryRequest.sqlHandlingMode.name,
          'max_rows_handling': 'response_truncation',
          'effective_max_rows': limits.maxRows,
          'rows': <Map<String, dynamic>>[],
          'row_count': 0,
          'affected_rows': totalRows,
          ...?(columnMetadata != null ? {'column_metadata': columnMetadata} : null),
        },
      );
      if (autoStreaming && !_featureFlags.enableSocketStreamingChunks) {
        switch (autoStreamingReason) {
          case _DbStreamingAutoReason.prefer:
            _dispatchMetrics?.recordSqlExecutePreferDbStreamingResponse();
          case _DbStreamingAutoReason.allowlist:
            _dispatchMetrics?.recordSqlExecuteAutoStreamingFromDbResponse();
            _dispatchMetrics?.recordSqlExecuteAllowlistDbStreamingResponse();
          case _DbStreamingAutoReason.sqlLength:
          case _DbStreamingAutoReason.sqlSignal:
            _dispatchMetrics?.recordSqlExecuteAutoStreamingFromDbResponse();
          case _DbStreamingAutoReason.none:
            break;
        }
      }
      _dispatchMetrics?.recordSqlExecuteStreamingFromDbResponse();
      return dbStreamResponse;
    } finally {
      _activeStreamExecution = null;
    }
  }

  bool _isDbStreamingDriverAllowed(String driverName) {
    return switch (DatabaseDriver.fromString(driverName)) {
      DatabaseDriver.sqlServer => true,
      DatabaseDriver.postgreSQL => true,
      DatabaseDriver.sqlAnywhere => true,
      DatabaseDriver.unknown => false,
    };
  }

  _DbStreamingAutoReason _dbStreamingAutoReason({
    required QueryRequest queryRequest,
    required String sql,
    required Map<String, dynamic> negotiatedExtensions,
    required bool preferDbStreaming,
  }) {
    if (!_featureFlags.enableSocketStreamingFromDb ||
        _featureFlags.enableSocketStreamingChunks ||
        !_supportsStreamingChunks(negotiatedExtensions) ||
        queryRequest.pagination != null ||
        queryRequest.expectMultipleResults ||
        (queryRequest.parameters?.isNotEmpty ?? false)) {
      return _DbStreamingAutoReason.none;
    }

    final normalized = ' ${sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()} ';
    if (!normalized.startsWith(' select ') && !normalized.startsWith(' with ')) {
      return _DbStreamingAutoReason.none;
    }
    if (_containsExplicitRowLimit(normalized)) {
      return _DbStreamingAutoReason.none;
    }
    if (preferDbStreaming) {
      return _DbStreamingAutoReason.prefer;
    }
    if (_requiresExplicitDbStreamingPreference(normalized)) {
      return _DbStreamingAutoReason.none;
    }
    if (normalized.length >= _dbStreamingAutoSqlLengthThreshold) {
      return _DbStreamingAutoReason.sqlLength;
    }
    if (_matchesDbStreamingAutoTableAllowlist(normalized)) {
      return _DbStreamingAutoReason.allowlist;
    }
    if (_dbStreamingAutoLargeSqlSignals.any(normalized.contains)) {
      return _DbStreamingAutoReason.sqlSignal;
    }
    return _DbStreamingAutoReason.none;
  }

  bool _matchesDbStreamingAutoTableAllowlist(String normalizedSql) {
    final allowlist = _dbStreamingAutoTableAllowlist();
    if (allowlist.isEmpty) {
      return false;
    }
    if (allowlist.contains('*')) {
      return true;
    }

    final tableName = _firstTableNameForDbStreaming(normalizedSql);
    return tableName != null && allowlist.contains(tableName);
  }

  bool _requiresExplicitDbStreamingPreference(String normalizedSql) {
    return normalizedSql.startsWith(' with ') ||
        normalizedSql.contains(' join ') ||
        RegExp(r'\bfrom\s*\(', caseSensitive: false).hasMatch(normalizedSql);
  }

  Set<String> _dbStreamingAutoTableAllowlist() {
    final now = DateTime.now();
    final expiresAt = _cachedDbStreamingAutoTableAllowlistExpiresAt;
    final rawAllowlist = AppEnvironment.get(_dbStreamingAutoTableAllowlistEnv);
    if (expiresAt != null && now.isBefore(expiresAt) && rawAllowlist == _cachedDbStreamingAutoTableAllowlistRaw) {
      return _cachedDbStreamingAutoTableAllowlist;
    }

    _cachedDbStreamingAutoTableAllowlistRaw = rawAllowlist;
    _cachedDbStreamingAutoTableAllowlistExpiresAt = now.add(_dbStreamingAutoTableAllowlistCacheTtl);
    if (rawAllowlist == null) {
      return _cachedDbStreamingAutoTableAllowlist = const <String>{};
    }

    return _cachedDbStreamingAutoTableAllowlist = rawAllowlist
        .split(',')
        .map(_normalizeDbStreamingTableName)
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String? _firstTableNameForDbStreaming(String normalizedSql) {
    final match = RegExp(r'\bfrom\s+([a-z0-9_\.\[\]"]+)', caseSensitive: false).firstMatch(normalizedSql);
    final table = match?.group(1);
    if (table == null) {
      return null;
    }
    return _normalizeDbStreamingTableName(table);
  }

  String _normalizeDbStreamingTableName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'^[\["]+|[\]"]+$'), '').replaceAll(RegExp(r'[\[\]"]'), '');
  }

  bool _containsExplicitRowLimit(String normalizedSql) {
    return normalizedSql.contains(' top ') ||
        normalizedSql.contains(' limit ') ||
        normalizedSql.contains(' fetch first ') ||
        normalizedSql.contains(' offset ') ||
        RegExp(r'\brownum\s*<=', caseSensitive: false).hasMatch(normalizedSql);
  }

  /// Handles sql.executeBatch method (multiple commands).
  Future<RpcResponse> _handleSqlExecuteBatch(
    RpcRequest request,
    String agentId,
    String? clientToken, {
    required TransportLimits limits,
    required Map<String, dynamic> negotiatedExtensions,
  }) async {
    // Validate params
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final commandsJson = params['commands'] as List<dynamic>?;
    final deadline = _featureFlags.enableSocketTimeoutByStage ? DateTime.now().add(_sqlBatchTotalBudgetDuration) : null;
    if (!_supportsPageOffsetPagination(negotiatedExtensions)) {
      final options = params['options'] as Map<String, dynamic>?;
      if (options?['page'] != null || options?['page_size'] != null) {
        return _invalidParams(
          request,
          'Negotiated protocol does not allow page-offset pagination',
        );
      }
    }

    if (commandsJson == null || commandsJson.isEmpty) {
      return _invalidParams(
        request,
        'commands is required and must not be empty',
      );
    }

    if (commandsJson.length > limits.maxBatchSize) {
      return _invalidParams(
        request,
        'commands exceeds negotiated limit: '
        '${commandsJson.length} > ${limits.maxBatchSize}',
      );
    }

    final idempotencyKey = params['idempotency_key'] as String?;
    final idempotencyFingerprint = await resolveIdempotencyFingerprint(
      request.method,
      params,
    );
    final idempotentEarly = await _consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint,
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    // Parse commands and build execution plan
    final commandPlans = <_BatchCommandExecutionPlan>[];
    for (var i = 0; i < commandsJson.length; i++) {
      final commandJson = commandsJson[i];
      if (commandJson is! Map<String, dynamic>) {
        return _invalidParams(request, 'commands[$i] must be an object');
      }

      final executionOrderRaw = commandJson['execution_order'];
      final executionOrder = executionOrderRaw != null ? jsonNonNegativeInt(executionOrderRaw) : null;
      if (executionOrderRaw != null && executionOrder == null) {
        return _invalidParams(
          request,
          'commands[$i].execution_order must be an integer >= 0',
        );
      }

      commandPlans.add(
        _BatchCommandExecutionPlan(
          command: SqlCommand.fromJson(commandJson),
          requestIndex: i,
          executionOrder: executionOrder,
        ),
      );
    }

    commandPlans.sort((left, right) {
      final leftHasExplicitOrder = left.executionOrder != null;
      final rightHasExplicitOrder = right.executionOrder != null;

      if (leftHasExplicitOrder && rightHasExplicitOrder) {
        final orderCompare = left.executionOrder!.compareTo(
          right.executionOrder!,
        );
        if (orderCompare != 0) {
          return orderCompare;
        }
        return left.requestIndex.compareTo(right.requestIndex);
      }

      if (leftHasExplicitOrder && !rightHasExplicitOrder) {
        return -1;
      }
      if (!leftHasExplicitOrder && rightHasExplicitOrder) {
        return 1;
      }
      return left.requestIndex.compareTo(right.requestIndex);
    });

    final commands = commandPlans.map((plan) => plan.command).toList(growable: false);

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      _authMetrics?.recordDenied(
        requestId: request.id?.toString(),
        method: request.method,
        reason: RpcClientTokenConstants.missingClientTokenReason,
      );
      _recordAuthSqlDenied(
        request,
        sql: _sqlPreviewForBatch(commands),
        explicitReason: RpcClientTokenConstants.missingClientTokenReason,
      );
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final database = params['database'] as String?;

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authorizedSqlFingerprints = <String>{};
      for (final cmd in commands) {
        final authFingerprint = _authorizationFingerprint(cmd.sql);
        if (authorizedSqlFingerprints.contains(authFingerprint)) {
          continue;
        }

        final authStopwatch = Stopwatch()..start();
        final authResult = await _authorizeWithBudget(
          token: clientToken,
          sql: cmd.sql,
          requestDatabase: database,
          requestId: request.id?.toString(),
          method: request.method,
          deadline: deadline,
        );
        authStopwatch.stop();
        if (authResult.isError()) {
          final failure = authResult.exceptionOrNull()! as domain.Failure;
          final ctx = failure.context;
          _authMetrics?.recordDenied(
            requestId: request.id?.toString(),
            method: request.method,
            latencyMs: authStopwatch.elapsedMilliseconds,
            clientId: ctx['client_id'] as String?,
            operation: ctx['operation'] as String?,
            resource: ctx['resource'] as String?,
            reason: ctx['reason'] as String?,
          );
          _recordAuthSqlDenied(
            request,
            sql: cmd.sql,
            failure: failure,
          );
          final rpcError = FailureToRpcErrorMapper.map(
            failure,
            instance: request.id?.toString(),
            useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
          );
          return RpcResponse.error(id: request.id, error: rpcError);
        }
        _authMetrics?.recordAuthorized(
          requestId: request.id?.toString(),
          method: request.method,
          latencyMs: authStopwatch.elapsedMilliseconds,
        );
        authorizedSqlFingerprints.add(authFingerprint);
      }
    }

    // Parse options
    final optionsJson = params['options'] as Map<String, dynamic>?;
    final options = optionsJson != null ? SqlExecutionOptions.fromJson(optionsJson) : const SqlExecutionOptions();
    final effectiveOptions = SqlExecutionOptions(
      timeoutMs: options.timeoutMs,
      maxRows: options.maxRows < limits.maxRows ? options.maxRows : limits.maxRows,
      transaction: options.transaction,
      maxParallelReadOnlyBatchItems: options.maxParallelReadOnlyBatchItems,
    );

    // Execute batch
    final batchStartedAt = DateTime.now().toUtc();
    final result = await _executeSqlBatchWithBudget(
      agentId,
      commands,
      database: database,
      options: effectiveOptions,
      requestId: request.id?.toString(),
      deadline: deadline,
    );

    if (result.isError()) {
      final failure = result.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final commandResults = result.getOrThrow();
    final batchFinishedAt = DateTime.now().toUtc();
    final items =
        commandResults
            .map((SqlCommandResult batchResult) {
              if (batchResult.index < 0 || batchResult.index >= commandPlans.length) {
                return batchResult;
              }
              final requestIndex = commandPlans[batchResult.index].requestIndex;
              return SqlCommandResult(
                index: requestIndex,
                ok: batchResult.ok,
                rows: batchResult.rows,
                rowCount: batchResult.rowCount,
                affectedRows: batchResult.affectedRows,
                error: batchResult.error,
                columnMetadata: batchResult.columnMetadata,
              );
            })
            .toList(growable: false)
          ..sort((left, right) => left.index.compareTo(right.index));

    final resultData = {
      'execution_id': _uuid.v4(),
      'started_at': batchStartedAt.toIso8601String(),
      'finished_at': batchFinishedAt.toIso8601String(),
      'items': items.map((r) => r.toJson()).toList(growable: false),
      'total_commands': commands.length,
      'successful_commands': items.where((r) => r.ok).length,
      'failed_commands': items.where((r) => !r.ok).length,
    };

    final response = RpcResponse.success(
      id: request.id,
      result: resultData,
    );
    await _storeIdempotentSuccessIfApplicable(
      request: request,
      idempotencyKey: idempotencyKey,
      idempotencyFingerprint: idempotencyFingerprint,
      response: response,
    );
    return response;
  }

  Future<RpcResponse> _handleSqlBulkInsert(
    RpcRequest request,
    String? clientToken, {
    required TransportLimits limits,
  }) async {
    if (request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>;
    final bulkRequestResult = _parseBulkInsertRequest(request, params, limits);
    if (bulkRequestResult.isError()) {
      final failure = bulkRequestResult.exceptionOrNull()! as domain.Failure;
      return _invalidParams(request, failure.message);
    }
    final bulkRequest = bulkRequestResult.getOrThrow();
    final database = params['database'] as String?;
    final authorizationSql = _bulkInsertAuthorizationSql(bulkRequest);
    final deadline = _featureFlags.enableSocketTimeoutByStage ? DateTime.now().add(_sqlBatchTotalBudgetDuration) : null;

    final idempotencyKey = params['idempotency_key'] as String?;
    final idempotencyFingerprint = await resolveIdempotencyFingerprint(
      request.method,
      params,
    );
    final idempotentEarly = await _consumeIdempotentCacheIfAny(
      request,
      idempotencyKey,
      idempotencyFingerprint,
    );
    if (idempotentEarly != null) {
      return idempotentEarly;
    }

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      _authMetrics?.recordDenied(
        requestId: request.id?.toString(),
        method: request.method,
        reason: RpcClientTokenConstants.missingClientTokenReason,
      );
      _recordAuthSqlDenied(
        request,
        sql: authorizationSql,
        explicitReason: RpcClientTokenConstants.missingClientTokenReason,
      );
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authStopwatch = Stopwatch()..start();
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: authorizationSql,
        requestDatabase: database,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      authStopwatch.stop();
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final ctx = failure.context;
        _authMetrics?.recordDenied(
          requestId: request.id?.toString(),
          method: request.method,
          latencyMs: authStopwatch.elapsedMilliseconds,
          clientId: ctx['client_id'] as String?,
          operation: ctx['operation'] as String?,
          resource: ctx['resource'] as String?,
          reason: ctx['reason'] as String?,
        );
        _recordAuthSqlDenied(
          request,
          sql: authorizationSql,
          failure: failure,
        );
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
      _authMetrics?.recordAuthorized(
        requestId: request.id?.toString(),
        method: request.method,
        latencyMs: authStopwatch.elapsedMilliseconds,
      );
    }

    final options = params['options'] as Map<String, dynamic>?;
    final timeoutMs = jsonPositiveInt(options?['timeout_ms']) ?? 0;
    final startedAt = DateTime.now().toUtc();
    final result = await _executeBulkInsertWithBudget(
      bulkRequest,
      database: database,
      timeoutMs: timeoutMs,
      requestId: request.id?.toString(),
      deadline: deadline,
    );

    if (result.isError()) {
      final failure = result.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final insertedRows = result.getOrThrow();
    final finishedAt = DateTime.now().toUtc();
    final response = RpcResponse.success(
      id: request.id,
      result: {
        'execution_id': _uuid.v4(),
        'started_at': startedAt.toIso8601String(),
        'finished_at': finishedAt.toIso8601String(),
        'table': bulkRequest.table,
        'row_count': bulkRequest.rowCount,
        'inserted_rows': insertedRows,
      },
    );
    await _storeIdempotentSuccessIfApplicable(
      request: request,
      idempotencyKey: idempotencyKey,
      idempotencyFingerprint: idempotencyFingerprint,
      response: response,
    );
    return response;
  }

  Result<BulkInsertRequest> _parseBulkInsertRequest(
    RpcRequest request,
    Map<String, dynamic> params,
    TransportLimits limits,
  ) {
    const allowedKeys = {
      'table',
      'columns',
      'rows',
      'client_token',
      'clientToken',
      'auth',
      'idempotency_key',
      'options',
      'database',
    };
    final extraKeys = params.keys.where((key) => !allowedKeys.contains(key));
    if (extraKeys.isNotEmpty) {
      return Failure(
        domain.ValidationFailure(
          'Field "params" contains unsupported properties: ${extraKeys.join(", ")}',
        ),
      );
    }
    try {
      final bulkRequest = BulkInsertRequest.fromJson(params);
      final identifierFailure = _validateBulkInsertIdentifiers(bulkRequest);
      if (identifierFailure != null) {
        return Failure(identifierFailure);
      }
      if (bulkRequest.rows.length > limits.maxRows) {
        return Failure(
          domain.ValidationFailure(
            'Field "params.rows" exceeds negotiated limit: ${bulkRequest.rows.length} > ${limits.maxRows}',
          ),
        );
      }
      final options = params['options'];
      if (options != null && options is! Map<String, dynamic>) {
        return Failure(domain.ValidationFailure('Field "params.options" must be an object'));
      }
      if (options is Map<String, dynamic>) {
        final extraOptionKeys = options.keys.where((key) => key != 'timeout_ms');
        if (extraOptionKeys.isNotEmpty) {
          return Failure(
            domain.ValidationFailure(
              'Field "params.options" contains unsupported properties: ${extraOptionKeys.join(", ")}',
            ),
          );
        }
        final timeout = options['timeout_ms'];
        if (timeout != null && jsonPositiveInt(timeout) == null) {
          return Failure(domain.ValidationFailure('Field "params.options.timeout_ms" must be an integer >= 1'));
        }
      }
      final tokenValidation = _validateBulkInsertTokenAliases(params);
      if (tokenValidation != null) {
        return Failure(tokenValidation);
      }
      final idempotencyKey = params['idempotency_key'];
      if (idempotencyKey != null && (idempotencyKey is! String || idempotencyKey.trim().isEmpty)) {
        return Failure(domain.ValidationFailure('Field "params.idempotency_key" must be a non-empty string'));
      }
      final database = params['database'];
      if (database != null && database is! String) {
        return Failure(domain.ValidationFailure('Field "params.database" must be a string'));
      }
      return Success(bulkRequest);
    } on Object catch (error) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Invalid sql.bulkInsert params',
          cause: error,
          context: {'request_id': ?request.id?.toString()},
        ),
      );
    }
  }

  domain.ValidationFailure? _validateBulkInsertIdentifiers(
    BulkInsertRequest request,
  ) {
    if (!_bulkIdentifierPath.hasMatch(request.table)) {
      return domain.ValidationFailure('Field "params.table" must be a simple identifier path');
    }
    for (final column in request.columns) {
      if (!_bulkIdentifierPath.hasMatch(column.name)) {
        return domain.ValidationFailure('Field "params.columns[].name" must be a simple identifier');
      }
    }
    return null;
  }

  domain.ValidationFailure? _validateBulkInsertTokenAliases(Map<String, dynamic> params) {
    for (final key in ['client_token', 'clientToken', 'auth']) {
      final value = params[key];
      if (value != null && (value is! String || value.trim().isEmpty)) {
        return domain.ValidationFailure('Field "params.$key" must be a non-empty string');
      }
    }
    return null;
  }

  String _bulkInsertAuthorizationSql(BulkInsertRequest request) {
    final columns = request.columns.map((column) => column.name).join(', ');
    return 'INSERT INTO ${request.table} ($columns) VALUES (...)';
  }

  /// When [multiResultRequested] and the script contains several statements,
  /// authorizes each fragment separately (aligned with `sql.executeBatch`).
  ///
  /// Uses [sqlStatementsForClientTokenAuthorization]: one split pass for
  /// `multi_result` instead of a separate multi-statement probe plus split.
  Future<RpcResponse?> _authorizeSqlExecuteWithClientToken({
    required RpcRequest request,
    required String sql,
    required bool multiResultRequested,
    required String clientToken,
    required String? requestDatabase,
    required DateTime? deadline,
  }) async {
    final statements = !multiResultRequested ? <String>[sql] : sqlStatementsForClientTokenAuthorization(sql);

    final authorizedFingerprints = <String>{};
    for (final raw in statements) {
      final stmt = raw.trim();
      if (stmt.isEmpty) {
        continue;
      }
      final fingerprint = _authorizationFingerprint(stmt);
      if (authorizedFingerprints.contains(fingerprint)) {
        continue;
      }
      authorizedFingerprints.add(fingerprint);

      final authStopwatch = Stopwatch()..start();
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: stmt,
        requestDatabase: requestDatabase,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      authStopwatch.stop();
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final ctx = failure.context;
        _authMetrics?.recordDenied(
          requestId: request.id?.toString(),
          method: request.method,
          latencyMs: authStopwatch.elapsedMilliseconds,
          clientId: ctx['client_id'] as String?,
          operation: ctx['operation'] as String?,
          resource: ctx['resource'] as String?,
          reason: ctx['reason'] as String?,
        );
        _recordAuthSqlDenied(
          request,
          sql: stmt,
          failure: failure,
        );
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
      _authMetrics?.recordAuthorized(
        requestId: request.id?.toString(),
        method: request.method,
        latencyMs: authStopwatch.elapsedMilliseconds,
      );
    }
    return null;
  }

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

  Future<Result<QueryResponse>> _executeQueryWithBudget(
    QueryRequest queryRequest, {
    required String? database,
    required String? requestId,
    required DateTime? deadline,
    required int timeoutMs,
  }) async {
    final timeout = mergeOdbcTimeout(
      stageTimeout: _effectiveStageTimeout(
        deadline: deadline,
        stageBudget: _queryStageBudgetDuration,
      ),
      timeoutMs: timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': RpcSqlBudgetConstants.queryBudgetExhaustedReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      if (timeout == null) {
        if (database == null || database.isEmpty) {
          return await _databaseGateway.executeQuery(queryRequest);
        }
        return await _databaseGateway.executeQuery(
          queryRequest,
          database: database,
        );
      }
      return await _databaseGateway.executeQuery(
        queryRequest,
        timeout: timeout,
        database: database,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'query',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'SQL execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Future<Result<List<SqlCommandResult>>> _executeSqlBatchWithBudget(
    String agentId,
    List<SqlCommand> commands, {
    required String? database,
    required SqlExecutionOptions options,
    required String? requestId,
    required DateTime? deadline,
  }) async {
    final stageTimeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _batchExecutionStageBudgetDuration,
    );
    final timeout = mergeBatchOdbcTimeout(
      stageTimeout: stageTimeout,
      timeoutMs: options.timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'batch',
        'reason': RpcSqlBudgetConstants.batchBudgetExhaustedReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Batch execution budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      return await _executeSqlBatch(
        agentId,
        commands,
        database: database,
        options: options,
        timeout: timeout,
        sourceRpcRequestId: requestId,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'batch',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Batch SQL execution timeout',
          cause: error,
          context: context,
        ),
      );
    }
  }

  Future<Result<int>> _executeBulkInsertWithBudget(
    BulkInsertRequest request, {
    required String? database,
    required int timeoutMs,
    required String? requestId,
    required DateTime? deadline,
  }) async {
    final stageTimeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _batchExecutionStageBudgetDuration,
    );
    final timeout = mergeBatchOdbcTimeout(
      stageTimeout: stageTimeout,
      timeoutMs: timeoutMs,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'bulk_insert',
        'reason': RpcSqlBudgetConstants.bulkInsertBudgetExhaustedReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Bulk insert budget exhausted before database call',
          context: context,
        ),
      );
    }

    try {
      return await _databaseGateway.executeBulkInsert(
        request,
        database: database,
        timeout: timeout,
      );
    } on TimeoutException catch (error) {
      final context = <String, dynamic>{
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'bulk_insert',
        'reason': RpcSqlBudgetConstants.queryTimeoutReason,
      };
      if (requestId != null) {
        context['request_id'] = requestId;
      }
      return Failure(
        domain.QueryExecutionFailure.withContext(
          message: 'Bulk insert execution timeout',
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

  int _resolveRequestedTimeoutMs(Map<String, dynamic> params) {
    final options = params['options'] as Map<String, dynamic>?;
    return jsonPositiveInt(options?['timeout_ms']) ?? 0;
  }

  /// Handles sql.cancel method (cancels in-flight streaming execution).
  Future<RpcResponse> _handleSqlCancel(RpcRequest request) async {
    if (!_featureFlags.enableSocketCancelMethod) {
      return _methodNotFound(request);
    }

    final gateway = _streamingGateway;
    if (gateway == null) {
      return _executionNotFound(request);
    }

    if (request.params != null && request.params is! Map<String, dynamic>) {
      return _invalidParams(request, 'params must be an object');
    }

    final params = request.params as Map<String, dynamic>? ?? {};
    final executionId = params['execution_id'] as String?;
    final requestId = params['request_id'] as String?;

    if ((executionId == null || executionId.isEmpty) && (requestId == null || requestId.isEmpty)) {
      return _invalidParams(
        request,
        'At least one of execution_id or request_id is required',
      );
    }

    final activeExecution = _activeStreamExecution;
    if (!gateway.hasActiveStream || activeExecution == null) {
      return _executionNotFound(request);
    }

    if (!_matchesActiveExecution(
      executionId: executionId,
      requestId: requestId,
      activeExecution: activeExecution,
    )) {
      return _executionNotFound(request);
    }

    final cancelResult = await gateway.cancelActiveStream(
      executionId: activeExecution.executionId,
    );

    return cancelResult.fold(
      (_) {
        final resultData = <String, dynamic>{
          'cancelled': true,
          ...?(executionId != null ? {'execution_id': executionId} : null),
          ...?(requestId != null ? {'request_id': requestId} : null),
        };
        return RpcResponse.success(id: request.id, result: resultData);
      },
      (failure) {
        final rpcError = FailureToRpcErrorMapper.map(
          failure as domain.Failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  Future<RpcResponse> _handleAgentGetProfile(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    // Params structure and allowed keys are validated upstream by
    // RpcRequestSchemaValidator before dispatch reaches this method.

    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudgetDuration)
        : null;

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: _agentProfileAuthorizationSql,
        requestDatabase: null,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
    }

    final resolver = _activeConfigResolver;
    final repository = _configRepository;
    if (resolver == null && repository == null) {
      return _internalError(
        request,
        'Agent profile repository is not available',
      );
    }

    final result = resolver != null
        ? await resolver.resolveActiveOrFallback(
            metadataOnly: true,
          )
        : await repository!.getCurrentConfigMetadata();
    if (result.isError()) {
      final failure = result.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final config = result.getOrThrow();
    final profileResult = AgentProfile.fromConfig(config);
    if (profileResult.isError()) {
      final failure = profileResult.exceptionOrNull()! as domain.Failure;
      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final profile = profileResult.getOrThrow();
    final profileUpdatedAt = _resolveAgentProfileUpdatedAt(config);
    final includeDiagnostics = _readBoolParam(
      request.params,
      'include_diagnostics',
      defaultValue: false,
    );
    final payload = <String, dynamic>{
      'agent_id': agentId,
      'profile': profile.toJson(),
      if (config.hubProfileVersion != null) 'profile_version': config.hubProfileVersion,
      'updated_at': profileUpdatedAt,
      if (includeDiagnostics) 'odbc': await _collectOdbcDiagnosticsPayload(),
    };
    return RpcResponse.success(
      id: request.id,
      result: payload,
    );
  }

  String _resolveAgentProfileUpdatedAt(Config config) {
    if (config.hubProfileVersion != null) {
      final hubUpdatedAt = _normalizeIsoDateTime(config.hubProfileUpdatedAt);
      if (hubUpdatedAt != null) {
        return hubUpdatedAt;
      }
    }
    return config.updatedAt.toUtc().toIso8601String();
  }

  String? _normalizeIsoDateTime(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value.trim());
    return parsed?.toUtc().toIso8601String();
  }

  Future<RpcResponse> _handleAgentGetHealth(
    RpcRequest request,
    String? clientToken,
  ) async {
    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudgetDuration)
        : null;

    if (_featureFlags.enableClientTokenAuthorization && (clientToken == null || clientToken.isEmpty)) {
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    if (_featureFlags.enableClientTokenAuthorization && clientToken != null && clientToken.isNotEmpty) {
      final authResult = await _authorizeWithBudget(
        token: clientToken,
        sql: _agentProfileAuthorizationSql,
        requestDatabase: null,
        requestId: request.id?.toString(),
        method: request.method,
        deadline: deadline,
      );
      if (authResult.isError()) {
        final failure = authResult.exceptionOrNull()! as domain.Failure;
        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      }
    }

    final raw = await _healthService.getHealthStatusAsync();
    final result = json.decode(json.encode(raw)) as Map<String, dynamic>;
    return RpcResponse.success(
      id: request.id,
      result: result,
    );
  }

  Future<RpcResponse> _handleClientTokenGetPolicy(
    RpcRequest request,
    String agentId,
    String? clientToken,
  ) async {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return _invalidParams(
        request,
        'client_token.getPolicy requires enableClientTokenAuthorization',
        rpcReason: 'client_token_authorization_disabled',
      );
    }

    if (!_featureFlags.enableClientTokenPolicyIntrospection) {
      return _invalidParams(
        request,
        'client_token.getPolicy requires enableClientTokenPolicyIntrospection',
        rpcReason: 'client_token_introspection_disabled',
      );
    }

    if (clientToken == null || clientToken.isEmpty) {
      final rpcError = FailureToRpcErrorMapper.map(
        _buildMissingClientTokenFailure(),
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return RpcResponse.error(id: request.id, error: rpcError);
    }

    final scopeKey = '$agentId:${hashClientCredentialToken(clientToken)}';
    if (!_getPolicyRateLimiter.tryAcquire(scopeKey)) {
      _dispatchMetrics?.recordClientTokenGetPolicyRateLimited();
      return _clientTokenGetPolicyRateLimited(request);
    }

    final policyResult = await _getClientTokenPolicy.call(clientToken);
    return policyResult.fold(
      (ClientTokenPolicy policy) {
        _dispatchMetrics?.recordClientTokenGetPolicySuccess();
        return RpcResponse.success(
          id: request.id,
          result: policy.toRpcResultJson(),
        );
      },
      (Object failure) {
        final domainFailure = failure is domain.Failure
            ? failure
            : domain.ServerFailure.withContext(
                message: 'Unexpected error while resolving client token policy',
                context: {'unexpected_type': failure.runtimeType.toString()},
              );
        _dispatchMetrics?.recordClientTokenGetPolicyFailure(domainFailure);
        if (failure is! domain.Failure) {
          developer.log(
            'client_token.getPolicy unexpected failure type',
            name: 'rpc_method_dispatcher',
            level: 500,
            error: failure is Exception ? failure : null,
          );
        }
        final rpcError = FailureToRpcErrorMapper.map(
          domainFailure,
          instance: request.id?.toString(),
          useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
        );
        return RpcResponse.error(id: request.id, error: rpcError);
      },
    );
  }

  RpcResponse _clientTokenGetPolicyRateLimited(RpcRequest request) {
    const code = RpcErrorCode.rateLimited;
    final window = _clientTokenGetPolicyRateLimitWindowFields();
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'client_token.getPolicy rate limit exceeded for this agent and credential',
          correlationId: request.id?.toString(),
          reason: RpcClientTokenConstants.clientTokenGetPolicyRateLimitedReason,
          extra: {
            'method': request.method,
            'retry_after_ms': window['retry_after_ms'],
            'reset_at': window['reset_at'],
          },
        ),
      ),
    );
  }

  /// Next UTC minute boundary for the fixed window used by the getPolicy rate limiter.
  Map<String, dynamic> _clientTokenGetPolicyRateLimitWindowFields() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    final windowEndMs = ((ms ~/ 60000) + 1) * 60000;
    final retryAfterMs = windowEndMs - ms;
    final resetAt = DateTime.fromMillisecondsSinceEpoch(windowEndMs, isUtc: true).toIso8601String();
    return <String, dynamic>{
      'retry_after_ms': retryAfterMs,
      'reset_at': resetAt,
    };
  }

  Future<Map<String, dynamic>> _collectOdbcDiagnosticsPayload() async {
    final metricsService = _odbcNativeMetricsService;
    if (metricsService == null) {
      return const <String, dynamic>{'available': false};
    }

    final now = DateTime.now().toUtc();
    final cached = _odbcDiagnosticsCache;
    final expiresAt = _odbcDiagnosticsCacheExpiresAt;
    if (cached != null && expiresAt != null && now.isBefore(expiresAt)) {
      return cached;
    }

    final snapshotResult = await metricsService.collectSnapshot();
    final payload = snapshotResult.fold(
      (snapshot) => <String, dynamic>{
        'available': true,
        'snapshot': snapshot,
      },
      (failure) => <String, dynamic>{
        'available': false,
        'error': failure.toString(),
      },
    );
    _odbcDiagnosticsCache = payload;
    _odbcDiagnosticsCacheExpiresAt = now.add(_odbcDiagnosticsCacheTtl);
    return payload;
  }

  bool _readBoolParam(
    dynamic params,
    String key, {
    required bool defaultValue,
  }) {
    if (params is! Map<String, dynamic>) {
      return defaultValue;
    }
    final value = params[key];
    return value is bool ? value : defaultValue;
  }

  /// Returns execution not found error for sql.cancel.
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

  static const int _sqlInvestigationBatchPreviewMaxChars = 8000;

  String _sqlPreviewForBatch(List<SqlCommand> commands) {
    final joined = commands.map((SqlCommand c) => c.sql).join('\n---\n');
    if (joined.length <= _sqlInvestigationBatchPreviewMaxChars) {
      return joined;
    }
    return '${joined.substring(0, _sqlInvestigationBatchPreviewMaxChars)}\n... [truncated]';
  }

  String _authorizationFingerprint(String sql) {
    return sql.trim().replaceAll(_authorizationSqlWhitespaceCollapse, ' ').toLowerCase();
  }

  int _resolveMaxRows(Map<String, dynamic> params, int negotiatedMaxRows) {
    final options = params['options'] as Map<String, dynamic>?;
    final requestedMaxRows = jsonPositiveInt(options?['max_rows']);
    if (requestedMaxRows == null) {
      return negotiatedMaxRows;
    }
    return requestedMaxRows < negotiatedMaxRows ? requestedMaxRows : negotiatedMaxRows;
  }

  bool _resolveMultiResult(Map<String, dynamic> params) {
    final options = params['options'] as Map<String, dynamic>?;
    return options?['multi_result'] == true;
  }

  _ResolvedSqlHandlingMode _resolveSqlHandlingMode(
    Map<String, dynamic> params,
  ) {
    final options = params['options'] as Map<String, dynamic>?;
    if (options == null) {
      return const _ResolvedSqlHandlingMode(
        sqlHandlingMode: SqlHandlingMode.managed,
      );
    }

    final executionMode = options['execution_mode'];
    if (executionMode != null && executionMode is! String) {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'execution_mode must be a string',
      );
    }
    if (executionMode != null && executionMode != 'managed' && executionMode != 'preserve') {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'execution_mode must be "managed" or "preserve"',
      );
    }

    final preserveSql = options['preserve_sql'];
    if (preserveSql != null && preserveSql is! bool) {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'preserve_sql must be a boolean',
      );
    }
    if (preserveSql == true && executionMode == 'managed') {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'preserve_sql cannot be true when execution_mode is "managed"',
      );
    }

    if (preserveSql == true) {
      AppLogger.warning(
        'options.preserve_sql is deprecated; use options.execution_mode: '
        '"preserve" instead',
      );
    }

    final resolvedMode = executionMode == 'preserve' || preserveSql == true
        ? SqlHandlingMode.preserve
        : SqlHandlingMode.managed;
    final hasManagedPagination = options['page'] != null || options['page_size'] != null || options['cursor'] != null;
    if (resolvedMode == SqlHandlingMode.preserve && hasManagedPagination) {
      return const _ResolvedSqlHandlingMode(
        errorMessage: 'execution_mode "preserve" cannot be combined with page, page_size, or cursor',
      );
    }

    return _ResolvedSqlHandlingMode(sqlHandlingMode: resolvedMode);
  }

  _ResolvedPagination _resolvePagination(
    Map<String, dynamic> params,
    String sql,
    int negotiatedMaxRows,
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final options = params['options'] as Map<String, dynamic>?;
    final page = jsonPositiveInt(options?['page']);
    final pageSize = jsonPositiveInt(options?['page_size']);
    final cursor = options?['cursor'] as String?;
    if (page == null && pageSize == null && cursor == null) {
      return const _ResolvedPagination();
    }

    final paginationPlanResult = SqlValidator.validatePaginationQuery(sql);
    SqlPaginationPlan? plan;
    if (paginationPlanResult.isSuccess()) {
      plan = paginationPlanResult.getOrNull();
    } else {
      final failure = paginationPlanResult.exceptionOrNull()! as domain.Failure;
      final isMissingOrderBy = failure.message == 'Paginated queries must declare an explicit ORDER BY clause';
      if (cursor != null || !isMissingOrderBy) {
        return _ResolvedPagination(errorMessage: failure.message);
      }
    }

    if (cursor != null) {
      final stablePlan = plan;
      if (stablePlan == null) {
        return const _ResolvedPagination(
          errorMessage: 'Cursor pagination requires an explicit ORDER BY clause',
        );
      }
      if (page != null || pageSize != null) {
        return const _ResolvedPagination(
          errorMessage: 'cursor cannot be combined with page or page_size',
        );
      }
      if (!_supportsCursorKeysetPagination(negotiatedExtensions)) {
        return const _ResolvedPagination(
          errorMessage: 'Negotiated protocol does not allow cursor pagination',
        );
      }

      try {
        final decodedCursor = QueryPaginationCursor.fromToken(cursor);
        if (decodedCursor.pageSize > negotiatedMaxRows) {
          return _ResolvedPagination(
            errorMessage:
                'cursor page_size exceeds negotiated limit: '
                '${decodedCursor.pageSize} > $negotiatedMaxRows',
          );
        }
        if (decodedCursor.isStableCursor) {
          if (decodedCursor.queryHash != stablePlan.queryFingerprint) {
            return const _ResolvedPagination(
              errorMessage: 'cursor does not match the SQL query fingerprint',
            );
          }
          if (!_orderByMatchesPlan(decodedCursor.orderBy, stablePlan.orderBy)) {
            return const _ResolvedPagination(
              errorMessage: 'cursor ordering does not match the SQL ORDER BY',
            );
          }
        }

        return _ResolvedPagination(
          pagination: QueryPaginationRequest(
            page: decodedCursor.page,
            pageSize: decodedCursor.pageSize,
            cursor: cursor,
            offset: decodedCursor.offset,
            queryHash: decodedCursor.queryHash ?? stablePlan.queryFingerprint,
            orderBy: stablePlan.orderBy,
            lastRowValues: decodedCursor.lastRowValues,
          ),
        );
      } on Exception catch (e, stackTrace) {
        developer.log(
          'Pagination cursor parsing failed (invalid or malformed)',
          name: 'rpc_method_dispatcher',
          error: e,
          stackTrace: stackTrace,
        );
        return const _ResolvedPagination(
          errorMessage: 'cursor is invalid or malformed',
        );
      }
    }

    if (page == null || pageSize == null || page < 1 || pageSize < 1) {
      return const _ResolvedPagination(
        errorMessage: 'page and page_size must be provided together and be >= 1',
      );
    }
    if (!_supportsPageOffsetPagination(negotiatedExtensions)) {
      return const _ResolvedPagination(
        errorMessage: 'Negotiated protocol does not allow page-offset pagination',
      );
    }
    if (pageSize > negotiatedMaxRows) {
      return _ResolvedPagination(
        errorMessage:
            'page_size exceeds negotiated limit: '
            '$pageSize > $negotiatedMaxRows',
      );
    }

    return _ResolvedPagination(
      pagination: QueryPaginationRequest(
        page: page,
        pageSize: pageSize,
        queryHash: plan?.queryFingerprint,
        orderBy: plan?.orderBy ?? const [],
      ),
    );
  }

  Map<String, dynamic> _buildPaginationResult(QueryPaginationInfo pagination) {
    return {
      'page': pagination.page,
      'page_size': pagination.pageSize,
      'returned_rows': pagination.returnedRows,
      'has_next_page': pagination.hasNextPage,
      'has_previous_page': pagination.hasPreviousPage,
      if (pagination.currentCursor != null) 'current_cursor': pagination.currentCursor,
      if (pagination.nextCursor != null) 'next_cursor': pagination.nextCursor,
    };
  }

  Map<String, dynamic> _buildExecuteResultData(
    QueryResponse response, {
    required DateTime startedAt,
    required DateTime finishedAt,
    required List<Map<String, dynamic>> limitedRows,
    required bool wasTruncated,
    required SqlHandlingMode sqlHandlingMode,
    required int effectiveMaxRows,
    bool forceMultiResultEnvelope = false,
  }) {
    final resultData = <String, dynamic>{
      'execution_id': response.id,
      'started_at': startedAt.toIso8601String(),
      'finished_at': finishedAt.toIso8601String(),
      'sql_handling_mode': sqlHandlingMode.name,
      'max_rows_handling': 'response_truncation',
      'effective_max_rows': effectiveMaxRows,
      'rows': limitedRows,
      'row_count': limitedRows.length,
    };

    if (response.affectedRows != null) {
      resultData['affected_rows'] = response.affectedRows;
    }
    if (wasTruncated) {
      resultData['truncated'] = true;
    }
    if (response.columnMetadata != null) {
      resultData['column_metadata'] = response.columnMetadata;
    }
    if (response.pagination != null) {
      resultData['pagination'] = _buildPaginationResult(response.pagination!);
    }
    if (forceMultiResultEnvelope || response.hasMultiResult) {
      resultData['multi_result'] = true;
      resultData['result_set_count'] = response.resultSets.length;
      resultData['item_count'] = response.items.length;
      resultData['result_sets'] = response.resultSets.map(_buildResultSetPayload).toList(growable: false);
      resultData['items'] = response.items.map(_buildResponseItemPayload).toList(growable: false);
    }

    return resultData;
  }

  Map<String, dynamic> _buildResultSetPayload(
    QueryResultSet resultSet, {
    bool includeIndex = true,
  }) {
    return {
      if (includeIndex) 'index': resultSet.index,
      'rows': resultSet.rows,
      'row_count': resultSet.rowCount,
      if (resultSet.affectedRows != null) 'affected_rows': resultSet.affectedRows,
      if (resultSet.columnMetadata != null) 'column_metadata': resultSet.columnMetadata,
    };
  }

  Map<String, dynamic> _buildResponseItemPayload(QueryResponseItem item) {
    if (item.resultSet != null) {
      return {
        'type': 'result_set',
        'index': item.index,
        'result_set_index': item.resultSet!.index,
        ..._buildResultSetPayload(item.resultSet!, includeIndex: false),
      };
    }
    return {
      'type': 'row_count',
      'index': item.index,
      'affected_rows': item.rowCount,
    };
  }

  QueryResponse _applyMaxRowsToMultiResultSets(
    QueryResponse response,
    int maxRows,
  ) {
    if (response.resultSets.isEmpty) {
      return response;
    }
    final newSets = <QueryResultSet>[];
    for (final rs in response.resultSets) {
      final limited = truncateSqlResultRows(rs.rows, maxRows);
      newSets.add(
        QueryResultSet(
          index: rs.index,
          rows: limited,
          rowCount: limited.length,
          affectedRows: rs.affectedRows,
          columnMetadata: rs.columnMetadata,
        ),
      );
    }
    final newItems = response.items
        .map((QueryResponseItem item) {
          if (item.resultSet != null) {
            final idx = item.resultSet!.index;
            final match = newSets.firstWhere(
              (QueryResultSet s) => s.index == idx,
            );
            return QueryResponseItem.resultSet(
              index: item.index,
              resultSet: match,
            );
          }
          return item;
        })
        .toList(growable: false);
    final primary = newSets.isNotEmpty ? newSets.first : const QueryResultSet(index: 0, rows: [], rowCount: 0);
    return QueryResponse(
      id: response.id,
      requestId: response.requestId,
      agentId: response.agentId,
      data: primary.rows,
      affectedRows: response.affectedRows,
      timestamp: response.timestamp,
      error: response.error,
      columnMetadata: primary.columnMetadata,
      pagination: response.pagination,
      resultSets: newSets,
      items: newItems,
    );
  }

  bool _multiResultSetsWereTruncated(
    QueryResponse before,
    QueryResponse after,
  ) {
    if (before.resultSets.length != after.resultSets.length) {
      return true;
    }
    for (var i = 0; i < before.resultSets.length; i++) {
      if (before.resultSets[i].rows.length != after.resultSets[i].rows.length) {
        return true;
      }
    }
    return false;
  }

  bool _matchesActiveExecution({
    required String? executionId,
    required String? requestId,
    required _ActiveStreamExecution activeExecution,
  }) {
    final executionMatches = executionId != null && executionId == activeExecution.executionId;
    final requestMatches = requestId != null && requestId == activeExecution.requestId;
    return executionMatches || requestMatches;
  }

  bool _supportsPageOffsetPagination(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final modes = _negotiatedPaginationModes(negotiatedExtensions);
    return modes.contains('page-offset');
  }

  bool _supportsCursorKeysetPagination(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final modes = _negotiatedPaginationModes(negotiatedExtensions);
    return modes.contains('cursor-keyset') || modes.contains('cursor-offset');
  }

  bool _supportsStreamingChunks(Map<String, dynamic> negotiatedExtensions) {
    final streamingResults = negotiatedExtensions['streamingResults'];
    if (streamingResults is bool) {
      return streamingResults;
    }
    return true;
  }

  Set<String> _negotiatedPaginationModes(
    Map<String, dynamic> negotiatedExtensions,
  ) {
    final rawModes = negotiatedExtensions['paginationModes'];
    if (rawModes is! List<dynamic> || rawModes.isEmpty) {
      return {'page-offset', 'cursor-keyset', 'cursor-offset'};
    }
    return rawModes.whereType<String>().toSet();
  }

  bool _orderByMatchesPlan(
    List<QueryPaginationOrderTerm> cursorOrderBy,
    List<QueryPaginationOrderTerm> planOrderBy,
  ) {
    if (cursorOrderBy.length != planOrderBy.length) {
      return false;
    }

    for (var i = 0; i < cursorOrderBy.length; i++) {
      final left = cursorOrderBy[i];
      final right = planOrderBy[i];
      if (left.expression != right.expression ||
          left.lookupKey != right.lookupKey ||
          left.descending != right.descending) {
        return false;
      }
    }
    return true;
  }

  /// Emits `rpc:complete` with [status] so the hub can deterministically close
  /// a stream that ended without full success.
  ///
  /// Swallows emit errors and records a failure counter so the caller can
  /// return the RPC error response even when the terminal complete fails.
  Future<void> _emitTerminalComplete({
    required IRpcStreamEmitter streamEmitter,
    required String streamId,
    required dynamic requestId,
    required int totalRows,
    required StreamTerminalStatus status,
  }) async {
    try {
      await streamEmitter.emitComplete(
        RpcStreamComplete(
          streamId: streamId,
          requestId: requestId,
          totalRows: totalRows,
          terminalStatus: status,
        ),
      );
      _dispatchMetrics?.recordStreamTerminalCompleteEmitted();
    } on Object catch (error, stackTrace) {
      _dispatchMetrics?.recordStreamTerminalCompleteFailed();
      developer.log(
        'Failed to emit terminal rpc:complete '
        'stream_id=$streamId status=${status.name}',
        name: 'rpc.dispatcher',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _recordAuthSqlDenied(
    RpcRequest request, {
    required String sql,
    domain.Failure? failure,
    String? explicitReason,
  }) {
    if (!_featureFlags.enableDashboardSqlInvestigationFeed) {
      return;
    }
    final collector = _sqlInvestigation;
    if (collector == null) {
      return;
    }
    if (!request.method.startsWith('sql.')) {
      return;
    }

    var reason = explicitReason;
    String? clientId;
    String? operation;
    String? resource;
    if (failure != null) {
      final ctx = failure.context;
      reason ??= ctx['reason'] as String?;
      clientId = ctx['client_id'] as String?;
      operation = ctx['operation'] as String?;
      resource = ctx['resource'] as String?;
    }

    collector.recordAuthorizationDenied(
      method: request.method,
      originalSql: sql,
      rpcRequestId: request.id?.toString(),
      reason: reason,
      clientId: clientId,
      operation: operation,
      resource: resource,
    );
  }
}

class _ResolvedPagination {
  const _ResolvedPagination({
    this.pagination,
    this.errorMessage,
  });

  final QueryPaginationRequest? pagination;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

class _ResolvedSqlHandlingMode {
  const _ResolvedSqlHandlingMode({
    this.sqlHandlingMode,
    this.errorMessage,
  });

  final SqlHandlingMode? sqlHandlingMode;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
}

class _BatchCommandExecutionPlan {
  const _BatchCommandExecutionPlan({
    required this.command,
    required this.requestIndex,
    required this.executionOrder,
  });

  final SqlCommand command;
  final int requestIndex;
  final int? executionOrder;
}

class _ActiveStreamExecution {
  const _ActiveStreamExecution({
    required this.streamId,
    required this.executionId,
    required this.requestId,
  });

  final String streamId;
  final String executionId;
  final String? requestId;
}
