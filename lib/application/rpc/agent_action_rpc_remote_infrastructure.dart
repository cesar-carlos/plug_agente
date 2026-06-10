import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_method_handler_support.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';

class AgentActionRpcRemoteInfrastructure {
  AgentActionRpcRemoteInfrastructure({
    required FeatureFlags featureFlags,
    required AgentActionRpcMethodHandlerSupport support,
    IIdempotencyStore? idempotencyStore,
    BackfillAgentActionExecutionCorrelation? backfillAgentActionExecutionCorrelation,
    AgentActionRemoteRateLimiter? agentActionRemoteRateLimiter,
    AgentActionRemoteAuthorizationService? agentActionRemoteAuthorization,
    AgentActionRuntimeStateGuard? agentActionRuntimeStateGuard,
    AgentRuntimeIdentity? agentRuntimeIdentity,
    void Function()? onAgentActionRemoteRateLimited,
  }) : _featureFlags = featureFlags,
       _support = support,
       _idempotencyStore = idempotencyStore,
       _backfillAgentActionExecutionCorrelation = backfillAgentActionExecutionCorrelation,
       _agentActionRemoteRateLimiter = agentActionRemoteRateLimiter,
       _agentActionRemoteAuthorization = agentActionRemoteAuthorization,
       _agentActionRuntimeStateGuard = agentActionRuntimeStateGuard,
       _agentRuntimeIdentity = agentRuntimeIdentity,
       _onAgentActionRemoteRateLimited = onAgentActionRemoteRateLimited;

  final FeatureFlags _featureFlags;
  final AgentActionRpcMethodHandlerSupport _support;
  final IIdempotencyStore? _idempotencyStore;
  final BackfillAgentActionExecutionCorrelation? _backfillAgentActionExecutionCorrelation;
  final AgentActionRemoteRateLimiter? _agentActionRemoteRateLimiter;
  final AgentActionRemoteAuthorizationService? _agentActionRemoteAuthorization;
  final AgentActionRuntimeStateGuard? _agentActionRuntimeStateGuard;
  final AgentRuntimeIdentity? _agentRuntimeIdentity;
  final void Function()? _onAgentActionRemoteRateLimited;

  static final RegExp w3cTraceParentTraceIdSegment = RegExp(r'^[0-9a-fA-F]{32}$');

  String? trimmedOptionalRpcString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String? traceIdFromW3cTraceParent(String? traceParent) {
    final raw = traceParent?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final segments = raw.split('-');
    if (segments.length < 2) {
      return null;
    }
    final candidate = segments[1].trim();
    if (!w3cTraceParentTraceIdSegment.hasMatch(candidate)) {
      return null;
    }
    return candidate.toLowerCase();
  }

  String? trimmedAgentActionRpcCorrelationParam(
    RpcRequest request,
    String paramKey,
  ) {
    final params = request.params;
    if (params is! Map<String, dynamic>) {
      return null;
    }
    return trimmedOptionalRpcString(params[paramKey] as String?);
  }

  String? resolvedRemoteAgentActionTraceId(RpcRequest request) {
    final fromParams = trimmedAgentActionRpcCorrelationParam(
      request,
      AgentActionRpcConstants.agentActionRpcParamTraceId,
    );
    if (fromParams != null) {
      return fromParams;
    }
    final explicit = trimmedOptionalRpcString(request.meta?.traceId);
    if (explicit != null) {
      return explicit;
    }
    return traceIdFromW3cTraceParent(request.meta?.traceParent);
  }

  String resolvedRemoteAgentActionRequestedBy(RpcRequest request) {
    final fromParams = trimmedAgentActionRpcCorrelationParam(
      request,
      AgentActionRpcConstants.agentActionRpcParamRequestedBy,
    );
    if (fromParams != null) {
      return fromParams;
    }
    return trimmedOptionalRpcString(request.meta?.requestId) ??
        trimmedOptionalRpcString(request.meta?.agentId) ??
        trimmedOptionalRpcString(request.id?.toString()) ??
        'remote';
  }

  String? resolvedRemoteAgentActionIdempotencyKey(RpcRequest request) {
    return trimmedAgentActionRpcCorrelationParam(
      request,
      AgentActionRpcConstants.agentActionRpcParamIdempotencyKey,
    );
  }

  Map<String, dynamic> agentActionParamsForIdempotencyFingerprint(
    Map<String, dynamic> params,
  ) {
    return Map<String, dynamic>.fromEntries(
      params.entries.where(
        (MapEntry<String, dynamic> entry) =>
            !AgentActionRpcConstants.agentActionRpcCorrelationOnlyParamKeys.contains(entry.key),
      ),
    );
  }

  String? executionIdFromAgentActionRpcSuccessResult(dynamic result) {
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

  String? rpcErrorReasonFromData(RpcError error) {
    final data = error.data;
    if (data is Map<String, dynamic>) {
      final reason = data['reason'];
      if (reason is String && reason.trim().isNotEmpty) {
        return reason.trim();
      }
    }
    return null;
  }

  Future<AgentActionExecution> withRpcCorrelationBackfill(
    AgentActionExecution execution,
    RpcRequest request,
  ) async {
    final backfill = _backfillAgentActionExecutionCorrelation;
    if (backfill == null) {
      return execution;
    }
    final result = await backfill(
      execution: execution,
      traceId: resolvedRemoteAgentActionTraceId(request),
      requestedBy: resolvedRemoteAgentActionRequestedBy(request),
    );
    return result.fold(
      (AgentActionExecution updated) => updated,
      (_) => execution,
    );
  }

  Future<String> resolveAgentActionRpcIdempotencyFingerprint(
    RpcRequest request,
    Map<String, dynamic> params,
  ) async {
    final fingerprintParams = agentActionParamsForIdempotencyFingerprint(params);
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

  RpcResponse agentActionRemoteRateLimitedRpc(RpcRequest request, Duration? retryAfter) {
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

  RpcResponse? agentActionRpcGateResponse(RpcRequest request) {
    if (!_featureFlags.enableAgentActions) {
      return agentActionFeatureDisabledResponse(request);
    }
    if (_featureFlags.enableAgentActionsMaintenanceMode) {
      return agentActionMaintenanceModeResponse(request);
    }
    if (agentActionRuntimeSubsystemGateResponse(request) case final RpcResponse runtimeGated) {
      return runtimeGated;
    }
    return agentActionRemoteFeatureDisabledResponse(request);
  }

  /// Fast path for Hub RPC when the local subsystem is not accepting remote work
  /// (starting, draining, maintenance, disabled). Per-type degraded checks remain in
  /// [RunAgentActionLocally] after the action definition is loaded.
  RpcResponse? agentActionRuntimeSubsystemGateResponse(RpcRequest request) {
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

  String? trimmedAgentActionRpcStringParam(RpcRequest request, String key) {
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

  RpcResponse agentActionMaintenanceModeResponse(RpcRequest request) {
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

  RpcResponse agentActionFeatureDisabledResponse(RpcRequest request) {
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

  RpcResponse? agentActionRemoteFeatureDisabledResponse(RpcRequest request) {
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

  RpcResponse? tryApplyAgentActionRemoteRateLimit({
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
    return agentActionRemoteRateLimitedRpc(request, decision.retryAfter);
  }

  Future<({RpcResponse? denied, ClientTokenPolicy? policy})> authorizeAgentActionClientTokenIfNeeded({
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

  Future<ClientTokenPolicy?> resolveClientTokenPolicyForRemoteAuditRow({
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

  FeatureFlags get featureFlags => _featureFlags;

  AgentActionRpcMethodHandlerSupport get support => _support;

  IIdempotencyStore? get idempotencyStore => _idempotencyStore;
}
