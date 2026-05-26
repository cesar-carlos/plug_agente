import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_remote_audit_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_remote_audit_store.dart';
import 'package:uuid/uuid.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MemoryAuditStore implements IAgentActionRemoteAuditStore {
  final List<AgentActionRemoteAuditRecord> rows = <AgentActionRemoteAuditRecord>[];

  @override
  Future<void> append(AgentActionRemoteAuditRecord record) async {
    rows.add(record);
  }

  @override
  Future<List<AgentActionRemoteAuditRecord>> listRecent({int limit = 200}) async =>
      List<AgentActionRemoteAuditRecord>.from(rows);

  @override
  Future<int> deleteWhereOccurredBefore({
    required DateTime cutoffUtc,
    required int limit,
  }) async => 0;
}

AgentActionExecution _remoteExecution({
  AgentActionExecutionStatus status = AgentActionExecutionStatus.queued,
}) {
  return AgentActionExecution(
    id: 'exec-1',
    actionId: 'action-1',
    actionType: AgentActionType.commandLine,
    status: status,
    requestedAt: DateTime.utc(2026, 5, 18, 10),
    source: AgentActionRequestSource.remoteHub,
    idempotencyKey: 'idem-1',
    traceId: 'trace-1',
    requestedBy: 'hub-user',
    runtimeInstanceId: 'inst-exec',
    runtimeSessionId: 'sess-exec',
  );
}

void main() {
  late _MockFeatureFlags featureFlags;
  late _MemoryAuditStore store;
  late AgentActionRemoteLifecycleAuditRecorder recorder;

  setUp(() {
    featureFlags = _MockFeatureFlags();
    store = _MemoryAuditStore();
    recorder = AgentActionRemoteLifecycleAuditRecorder(
      featureFlags: featureFlags,
      auditStore: store,
      runtimeIdentity: const AgentRuntimeIdentity(
        runtimeInstanceId: 'inst-fallback',
        runtimeSessionId: 'sess-fallback',
      ),
      uuid: const Uuid(),
      now: () => DateTime.utc(2026, 5, 18, 12),
    );
  });

  test('should append lifecycle_enqueued when remote audit is enabled', () async {
    when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(true);

    await recorder.recordEnqueued(_remoteExecution());

    check(store.rows.length).equals(1);
    check(store.rows.single.outcome).equals(AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued);
    check(store.rows.single.rpcMethod).equals(AgentActionRpcConstants.agentActionRunRpcMethodName);
    check(store.rows.single.executionId).equals('exec-1');
    check(store.rows.single.traceId).equals('trace-1');
    check(store.rows.single.idempotencyKey).equals('idem-1');
    check(store.rows.single.runtimeInstanceId).equals('inst-exec');
  });

  test('should not append when remote audit flag is disabled', () async {
    when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(false);

    await recorder.recordEnqueued(_remoteExecution());

    check(store.rows).isEmpty();
  });

  test('should not append for non-remote execution source', () async {
    when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(true);

    await recorder.recordEnqueued(
      AgentActionExecution(
        id: 'exec-local',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime.utc(2026, 5, 18, 10),
        source: AgentActionRequestSource.localUi,
      ),
    );

    check(store.rows).isEmpty();
  });

  test('should append lifecycle_finished with execution status as reasonCode', () async {
    when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(true);

    await recorder.recordFinished(
      execution: _remoteExecution(status: AgentActionExecutionStatus.succeeded),
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    );

    check(store.rows.single.outcome).equals(AgentActionRemoteAuditConstants.outcomeLifecycleFinished);
    check(store.rows.single.reasonCode).equals('succeeded');
  });

  test('should append lifecycle_cancel_requested for cancel rpc method', () async {
    when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(true);

    await recorder.recordCancelRequested(_remoteExecution(status: AgentActionExecutionStatus.running));

    check(store.rows.single.outcome).equals(AgentActionRemoteAuditConstants.outcomeLifecycleCancelRequested);
    check(store.rows.single.rpcMethod).equals(AgentActionRpcConstants.agentActionCancelRpcMethodName);
  });
}
