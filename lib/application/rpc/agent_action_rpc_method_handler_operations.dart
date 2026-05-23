import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_remote_rate_limiter.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/application/rpc/agent_action_get_execution_output_options.dart';
import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/idempotency_fingerprint.dart';
import 'package:plug_agente/application/use_cases/backfill_agent_action_execution_correlation.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_via_remote_trigger.dart';
import 'package:plug_agente/application/use_cases/slice_agent_action_captured_output.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_captured_output_constants.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:uuid/uuid.dart';

typedef AgentActionRpcInvalidParams = RpcResponse Function(
  RpcRequest request,
  String detail, {
  String? rpcReason,
  Map<String, dynamic> extraFields,
});

typedef AgentActionRpcInternalError = RpcResponse Function(
  RpcRequest request,
  String detail,
);

typedef AgentActionRpcConsumeIdempotentCache = Future<RpcResponse?> Function(
  RpcRequest request,
  String? idempotencyKey,
  String idempotencyFingerprint,
);

typedef AgentActionRpcStoreIdempotentSuccess = Future<void> Function({
  required RpcRequest request,
  required String? idempotencyKey,
  required String idempotencyFingerprint,
  required RpcResponse response,
});

typedef AgentActionRpcRunIdempotentExecution = Future<RpcResponse> Function({
  required RpcRequest request,
  required String? idempotencyKey,
  required String idempotencyFingerprint,
  required Future<RpcResponse> Function() execute,
});

class AgentActionRpcMethodHandlerSupport {
  const AgentActionRpcMethodHandlerSupport({
    required this.invalidParams,
    required this.internalError,
    required this.consumeIdempotentCacheIfAny,
    required this.storeIdempotentSuccessIfApplicable,
    required this.runIdempotentExecution,
  });

  final AgentActionRpcInvalidParams invalidParams;
  final AgentActionRpcInternalError internalError;
  final AgentActionRpcConsumeIdempotentCache consumeIdempotentCacheIfAny;
  final AgentActionRpcStoreIdempotentSuccess storeIdempotentSuccessIfApplicable;
  final AgentActionRpcRunIdempotentExecution runIdempotentExecution;
}

class AgentActionRpcMethodHandlerOperations {
  AgentActionRpcMethodHandlerOperations({
    required Uuid uuid,
    required FeatureFlags featureFlags,
    required AgentActionRpcMethodHandlerSupport support,
    IIdempotencyStore? idempotencyStore,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    void Function()? onAgentActionRemoteAuditExecutionCorrelated,
    void Function()? onAgentActionRemoteRateLimited,
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
  }) : _uuid = uuid,
       _featureFlags = featureFlags,
       _support = support,
       _idempotencyStore = idempotencyStore,
       _dispatchMetrics = dispatchMetrics,
       _onAgentActionRemoteAuditExecutionCorrelated = onAgentActionRemoteAuditExecutionCorrelated,
       _onAgentActionRemoteRateLimited = onAgentActionRemoteRateLimited,
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
       _agentRuntimeIdentity = agentRuntimeIdentity;

  final Uuid _uuid;
  final FeatureFlags _featureFlags;
  final AgentActionRpcMethodHandlerSupport _support;
  final IIdempotencyStore? _idempotencyStore;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final void Function()? _onAgentActionRemoteAuditExecutionCorrelated;
  final void Function()? _onAgentActionRemoteRateLimited;
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

  static final RegExp _w3cTraceParentTraceIdSegment = RegExp(r'^[0-9a-fA-F]{32}$');

  String? _trimmedOptionalRpcString(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

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
    final notificationRejected =
        request.isNotification &&
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
    required bool correlateExecution,
    String? actionId,
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

  Future<RpcResponse> handleAgentActionRun(
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
      response = _support.internalError(
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
        response = _support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _support.invalidParams(request, 'params must be an object');
      } else if (actionId.isEmpty) {
        response = _support.invalidParams(request, 'params.action_id is required');
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
              idempotentEarly = await _support.consumeIdempotentCacheIfAny(
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
              response = await _support.runIdempotentExecution(
                request: request,
                idempotencyKey: idempotencyKeyForCache,
                idempotencyFingerprint: idempotencyFingerprint,
                execute: () async {
                  final result = await runner(
                    actionId: actionId,
                    idempotencyKey: idempotencyKey,
                    triggerId: triggerId,
                    requestedBy: requestedBy,
                    traceId: traceId,
                  );
                  return result.fold<Future<RpcResponse>>(
                    (AgentActionExecution execution) async => RpcResponse.success(
                      id: request.id,
                      result: agentActionExecutionToGetExecutionResult(
                        execution,
                        sanitizeForRemoteHub: true,
                      ),
                    ),
                    (Exception failure) async => RpcResponse.error(
                      id: request.id,
                      error: FailureToRpcErrorMapper.map(
                        failure as domain.Failure,
                        instance: request.id?.toString(),
                        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                      ),
                    ),
                  );
                },
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

  Future<RpcResponse> handleAgentActionValidateRun(
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
      response = _support.internalError(request, 'Agent action execution is not configured on this dispatcher.');
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
        response = _support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _support.invalidParams(request, 'params must be an object');
      } else if (actionId.isEmpty) {
        response = _support.invalidParams(request, 'params.action_id is required');
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
              idempotentEarly = await _support.consumeIdempotentCacheIfAny(
                request,
                idempotencyKeyForCache,
                idempotencyFingerprint,
              );
            }
            if (idempotentEarly != null) {
              response = idempotentEarly;
            } else {
              response = await _support.runIdempotentExecution(
                request: request,
                idempotencyKey: idempotencyKeyForCache,
                idempotencyFingerprint: idempotencyFingerprint,
                execute: () async {
                  final result = await runner.validateRemoteRun(
                    AgentActionExecutionRequest(
                      actionId: actionId,
                      source: AgentActionRequestSource.remoteHub,
                      idempotencyKey: idempotencyKey,
                      requestedBy: requestedBy,
                      traceId: traceId,
                    ),
                  );
                  return result.fold<Future<RpcResponse>>(
                    (AgentActionValidateRunSummary summary) async => RpcResponse.success(
                      id: request.id,
                      result: summary.toRpcResultJson(),
                    ),
                    (Exception failure) async => RpcResponse.error(
                      id: request.id,
                      error: FailureToRpcErrorMapper.map(
                        failure as domain.Failure,
                        instance: request.id?.toString(),
                        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
                      ),
                    ),
                  );
                },
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

  Future<RpcResponse> handleAgentActionCancel(
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
      response = _support.internalError(request, 'Agent action cancel is not configured on this dispatcher.');
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
        response = _support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _support.invalidParams(request, 'params must be an object');
      } else if (executionId.isEmpty) {
        response = _support.invalidParams(request, 'params.execution_id is required');
      } else {
        final trimmedCredential = clientToken?.trim();
        final needsAgentActionPolicyContext =
            _featureFlags.enableClientTokenAuthorization && trimmedCredential != null && trimmedCredential.isNotEmpty;
        RpcResponse? prefetchFailureResponse;
        var executionActionIdForPolicy = '';
        if (needsAgentActionPolicyContext) {
          final lookup = _getAgentActionExecution;
          if (lookup == null) {
            prefetchFailureResponse = _support.internalError(
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

  Future<RpcResponse> handleAgentActionGetExecution(
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
      response = _support.internalError(request, 'Agent action execution lookup is not configured on this dispatcher.');
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
        response = _support.invalidParams(
          request,
          '${request.method} requires a JSON-RPC id',
          rpcReason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
        );
      } else if (request.params is! Map<String, dynamic>) {
        response = _support.invalidParams(request, 'params must be an object');
      } else if (executionId.isEmpty) {
        response = _support.invalidParams(request, 'params.execution_id is required');
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
}
