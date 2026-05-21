import 'dart:async';

import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/constants/rpc_sql_budget_constants.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_policy_agent_action_authorization.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:result_dart/result_dart.dart';

/// Authorizes remote `agent.action.*` RPC via client-token policy scopes/allowlist
/// and dedicated synthetic SQL resources (not general SQL table permissions).
class AgentActionRemoteAuthorizationService {
  AgentActionRemoteAuthorizationService({
    required FeatureFlags featureFlags,
    required GetClientTokenPolicy getClientTokenPolicy,
    required AuthorizeSqlOperation authorizeSqlOperation,
    Duration authorizationStageBudget = const Duration(seconds: 5),
    void Function()? onPermissionDenied,
  }) : _featureFlags = featureFlags,
       _getClientTokenPolicy = getClientTokenPolicy,
       _authorizeSqlOperation = authorizeSqlOperation,
       _authorizationStageBudget = authorizationStageBudget,
       _onPermissionDenied = onPermissionDenied;

  final FeatureFlags _featureFlags;
  final GetClientTokenPolicy _getClientTokenPolicy;
  final AuthorizeSqlOperation _authorizeSqlOperation;
  final Duration _authorizationStageBudget;
  final void Function()? _onPermissionDenied;

  Future<({RpcResponse? denied, ClientTokenPolicy? policy})> authorizeIfNeeded({
    required RpcRequest request,
    required String? clientToken,
    required String authorizationSql,
    required String requiredAgentActionScope,
    required String actionIdForAllowlist,
  }) async {
    if (!_featureFlags.enableClientTokenAuthorization) {
      return (denied: null, policy: null);
    }
    final trimmed = clientToken?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return (denied: _missingClientTokenResponse(request), policy: null);
    }

    final deadline = _featureFlags.enableSocketTimeoutByStage
        ? DateTime.now().add(_authorizationStageBudget)
        : null;
    final policyResult = await _getClientTokenPolicy.call(trimmed);
    if (!policyResult.isSuccess()) {
      final raw = policyResult.exceptionOrNull()!;
      final domainFailure = raw is domain.Failure
          ? raw
          : domain.ServerFailure.withContext(
              message: 'Unexpected error while resolving client token policy',
              context: {'unexpected_type': raw.runtimeType.toString()},
            );
      final rpcError = FailureToRpcErrorMapper.map(
        domainFailure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      );
      return (denied: RpcResponse.error(id: request.id, error: rpcError), policy: null);
    }

    final policy = policyResult.getOrThrow();
    if (!ClientTokenPolicyAgentActionAuthorization.grantsRemoteAgentAction(
      policyPayload: policy.payload,
      requiredScope: requiredAgentActionScope,
      actionId: actionIdForAllowlist,
    )) {
      _onPermissionDenied?.call();
      return (
        denied: _scopeDeniedResponse(
          request,
          requiredScope: requiredAgentActionScope,
          actionIdForAllowlist: actionIdForAllowlist,
        ),
        policy: policy,
      );
    }

    final authResult = await _authorizeSqlWithBudget(
      token: trimmed,
      sql: authorizationSql,
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
      return (denied: RpcResponse.error(id: request.id, error: rpcError), policy: policy);
    }

    return (denied: null, policy: policy);
  }

  /// Resolves policy for audit rows when authorization did not run but remote audit is on.
  Future<ClientTokenPolicy?> resolvePolicyForAudit({
    required String? clientToken,
    ClientTokenPolicy? fromAuthorization,
  }) async {
    if (fromAuthorization != null) {
      return fromAuthorization;
    }
    if (!_featureFlags.enableAgentActionRemoteAudit) {
      return null;
    }
    final trimmed = clientToken?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final result = await _getClientTokenPolicy.call(trimmed);
    return result.getOrNull();
  }

  static String? auditClientId(ClientTokenPolicy? policy) {
    if (policy == null) {
      return null;
    }
    final trimmed = policy.clientId.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? auditTokenJti(ClientTokenPolicy? policy) {
    if (policy == null) {
      return null;
    }
    final trimmed = policy.tokenId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  RpcResponse _missingClientTokenResponse(RpcRequest request) {
    final failure = domain.ConfigurationFailure.withContext(
      message: 'Client token is required for remote agent action RPC',
      context: <String, dynamic>{
        'authentication': true,
        'reason': RpcClientTokenConstants.missingClientTokenReason,
        'method': request.method,
      },
    );
    return RpcResponse.error(
      id: request.id,
      error: FailureToRpcErrorMapper.map(
        failure,
        instance: request.id?.toString(),
        useTimeoutByStage: _featureFlags.enableSocketTimeoutByStage,
      ),
    );
  }

  RpcResponse _scopeDeniedResponse(
    RpcRequest request, {
    required String requiredScope,
    required String actionIdForAllowlist,
  }) {
    const code = RpcErrorCode.unauthorized;
    final trimmedActionId = actionIdForAllowlist.trim();
    return RpcResponse.error(
      id: request.id,
      error: RpcError(
        code: code,
        message: RpcErrorCode.getMessage(code),
        data: RpcErrorCode.buildErrorData(
          code: code,
          technicalMessage: 'Client token policy does not grant the required agent action scope or action allowlist',
          correlationId: request.id?.toString(),
          reason: AgentActionRpcConstants.agentActionPermissionDeniedErrorReason,
          extra: <String, dynamic>{
            'method': request.method,
            'required_scope': requiredScope,
            if (trimmedActionId.isNotEmpty) 'action_id': trimmedActionId,
          },
        ),
      ),
    );
  }

  Future<Result<void>> _authorizeSqlWithBudget({
    required String token,
    required String sql,
    required String? requestId,
    required String method,
    required DateTime? deadline,
  }) async {
    final timeout = _effectiveStageTimeout(
      deadline: deadline,
      stageBudget: _authorizationStageBudget,
    );
    if (timeout != null && timeout <= Duration.zero) {
      final context = <String, dynamic>{
        'authorization': true,
        'reason': RpcSqlBudgetConstants.authorizationBudgetExhaustedReason,
        'timeout': true,
        'timeout_stage': 'sql',
        'stage': 'authorization',
        'method': method,
        'request_id': ?requestId,
      };
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
          requestId: requestId,
          method: method,
        );
      }
      return await _authorizeSqlOperation(
        token: token,
        sql: sql,
        requestId: requestId,
        method: method,
      ).timeout(timeout);
    } on TimeoutException catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Authorization stage timeout',
          cause: error,
          context: {
            'authorization': true,
            'reason': RpcSqlBudgetConstants.authorizationTimeoutReason,
            'timeout': true,
            'timeout_stage': 'sql',
            'stage': 'authorization',
            'method': method,
            'request_id': ?requestId,
          },
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
}
