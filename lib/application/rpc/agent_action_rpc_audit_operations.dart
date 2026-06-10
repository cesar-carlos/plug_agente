import 'dart:developer' as developer;

import 'package:plug_agente/application/rpc/agent_action_remote_authorization_service.dart';
import 'package:plug_agente/application/rpc/agent_action_rpc_remote_infrastructure.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/rpc_client_token_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:uuid/uuid.dart';

class AgentActionRpcAuditOperations {
  AgentActionRpcAuditOperations({
    required Uuid uuid,
    required FeatureFlags featureFlags,
    required AgentActionRpcRemoteInfrastructure infrastructure,
    IAgentActionRemoteAuditStore? agentActionRemoteAuditStore,
    IRpcDispatchMetricsCollector? dispatchMetrics,
    AgentRuntimeIdentity? agentRuntimeIdentity,
    void Function()? onAgentActionRemoteAuditExecutionCorrelated,
  }) : _uuid = uuid,
       _featureFlags = featureFlags,
       _infrastructure = infrastructure,
       _agentActionRemoteAuditStore = agentActionRemoteAuditStore,
       _dispatchMetrics = dispatchMetrics,
       _agentRuntimeIdentity = agentRuntimeIdentity,
       _onAgentActionRemoteAuditExecutionCorrelated = onAgentActionRemoteAuditExecutionCorrelated;

  final Uuid _uuid;
  final FeatureFlags _featureFlags;
  final AgentActionRpcRemoteInfrastructure _infrastructure;
  final IAgentActionRemoteAuditStore? _agentActionRemoteAuditStore;
  final IRpcDispatchMetricsCollector? _dispatchMetrics;
  final AgentRuntimeIdentity? _agentRuntimeIdentity;
  final void Function()? _onAgentActionRemoteAuditExecutionCorrelated;

  Future<RpcResponse> finishAgentActionRpcWithAudit({
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
        _infrastructure.rpcErrorReasonFromData(response.error!) ==
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
    final reason = response.error != null ? _infrastructure.rpcErrorReasonFromData(response.error!) : null;
    final outcome = resolveRemoteAuditOutcome(
      response: response,
      notificationRejected: notificationRejected,
      reasonCode: reason,
    );
    final effectiveExecutionId =
        executionId ??
        (response.isSuccess ? _infrastructure.executionIdFromAgentActionRpcSuccessResult(response.result) : null);
    await appendAgentActionRemoteAuditRecord(
      request: request,
      rpcMethod: rpcMethod,
      outcome: outcome,
      credentialPresent: credentialPresent,
      actionId: actionId,
      executionId: effectiveExecutionId,
      idempotencyKey: idempotencyKey ?? _infrastructure.resolvedRemoteAgentActionIdempotencyKey(request),
      reasonCode: reason,
      rpcErrorCode: errCode,
      resolvedClientTokenPolicy: resolvedClientTokenPolicy,
      correlateExecution: true,
    );
    return response;
  }

  String resolveRemoteAuditOutcome({
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

  Future<void> appendAgentActionRemoteAuditReceived({
    required RpcRequest request,
    required String rpcMethod,
    required bool credentialPresent,
    String? actionId,
    String? executionId,
    String? idempotencyKey,
    ClientTokenPolicy? resolvedClientTokenPolicy,
  }) async {
    await appendAgentActionRemoteAuditRecord(
      request: request,
      rpcMethod: rpcMethod,
      outcome: AgentActionRemoteAuditConstants.outcomeReceived,
      credentialPresent: credentialPresent,
      actionId: actionId,
      executionId: executionId,
      idempotencyKey: idempotencyKey ?? _infrastructure.resolvedRemoteAgentActionIdempotencyKey(request),
      resolvedClientTokenPolicy: resolvedClientTokenPolicy,
      correlateExecution: false,
    );
  }

  Future<void> appendAgentActionRemoteAuditRecord({
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
          traceId: _infrastructure.resolvedRemoteAgentActionTraceId(request),
          requestedBy: _infrastructure.resolvedRemoteAgentActionRequestedBy(request),
          reasonCode: reasonCode,
          rpcErrorCode: rpcErrorCode,
          clientId: AgentActionRemoteAuthorizationService.auditClientId(resolvedClientTokenPolicy),
          tokenJti: AgentActionRemoteAuthorizationService.auditTokenJti(resolvedClientTokenPolicy),
          runtimeInstanceId: _agentRuntimeIdentity?.runtimeInstanceId,
          runtimeSessionId: _agentRuntimeIdentity?.runtimeSessionId,
          idempotencyKey: idempotencyKey ?? _infrastructure.resolvedRemoteAgentActionIdempotencyKey(request),
        ),
      );
      if (correlateExecution) {
        recordRemoteAuditExecutionCorrelatedIfApplicable(executionId: executionId);
      }
    } on Exception catch (e, stackTrace) {
      final trace = _infrastructure.resolvedRemoteAgentActionTraceId(request);
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

  void recordRemoteAuditExecutionCorrelatedIfApplicable({
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
}
