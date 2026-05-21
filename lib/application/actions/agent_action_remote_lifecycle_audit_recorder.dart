import 'dart:developer' as developer;

import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:uuid/uuid.dart';

/// Append-only lifecycle audit for remote-hub executions (no secrets, best effort).
final class AgentActionRemoteLifecycleAuditRecorder {
  AgentActionRemoteLifecycleAuditRecorder({
    required FeatureFlags featureFlags,
    required IAgentActionRemoteAuditStore auditStore,
    required AgentRuntimeIdentity runtimeIdentity,
    required Uuid uuid,
    DateTime Function()? now,
  }) : _featureFlags = featureFlags,
       _auditStore = auditStore,
       _runtimeIdentity = runtimeIdentity,
       _uuid = uuid,
       _now = now ?? DateTime.now;

  final FeatureFlags _featureFlags;
  final IAgentActionRemoteAuditStore _auditStore;
  final AgentRuntimeIdentity _runtimeIdentity;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<void> recordEnqueued(AgentActionExecution execution) => _record(
    execution: execution,
    rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    outcome: AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued,
  );

  Future<void> recordStarted(AgentActionExecution execution) => _record(
    execution: execution,
    rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    outcome: AgentActionRemoteAuditConstants.outcomeLifecycleStarted,
  );

  Future<void> recordCancelRequested(AgentActionExecution execution) => _record(
    execution: execution,
    rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
    outcome: AgentActionRemoteAuditConstants.outcomeLifecycleCancelRequested,
  );

  Future<void> recordFinished({
    required AgentActionExecution execution,
    required String rpcMethod,
  }) => _record(
    execution: execution,
    rpcMethod: rpcMethod,
    outcome: AgentActionRemoteAuditConstants.outcomeLifecycleFinished,
    reasonCode: execution.status.name,
  );

  Future<void> _record({
    required AgentActionExecution execution,
    required String rpcMethod,
    required String outcome,
    String? reasonCode,
  }) async {
    if (!_featureFlags.enableAgentActionRemoteAudit) {
      return;
    }
    if (execution.source != AgentActionRequestSource.remoteHub) {
      return;
    }

    try {
      await _auditStore.append(
        AgentActionRemoteAuditRecord(
          id: _uuid.v4(),
          occurredAtUtc: _now().toUtc(),
          rpcMethod: rpcMethod,
          outcome: outcome,
          credentialPresent: false,
          actionId: execution.actionId,
          executionId: execution.id,
          traceId: execution.traceId,
          requestedBy: execution.requestedBy,
          idempotencyKey: execution.idempotencyKey,
          reasonCode: reasonCode,
          runtimeInstanceId: execution.runtimeInstanceId ?? _runtimeIdentity.runtimeInstanceId,
          runtimeSessionId: execution.runtimeSessionId ?? _runtimeIdentity.runtimeSessionId,
        ),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'agent.action remote lifecycle audit append failed (best effort) '
        'rpcMethod=$rpcMethod outcome=$outcome executionId=${execution.id}',
        name: 'agent_action_remote_lifecycle_audit',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
