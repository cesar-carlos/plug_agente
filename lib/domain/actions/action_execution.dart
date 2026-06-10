import 'package:plug_agente/domain/actions/action_adapter.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';

class AgentActionExecutionRequest {
  const AgentActionExecutionRequest({
    required this.actionId,
    required this.source,
    this.idempotencyKey,
    this.requestedBy,
    this.traceId,
    this.runtimeParameters = const {},
    this.contextPath,
    this.returnWhenQueued = false,
    this.dangerousCommandConfirmed = false,
    this.triggerId,
    this.triggerType,
    this.scheduledAt,
    this.triggeredAt,
    this.cachedPreparedExecution,
  });

  final String actionId;
  final AgentActionRequestSource source;
  final String? idempotencyKey;
  final String? requestedBy;
  final String? traceId;
  final Map<String, Object?> runtimeParameters;
  final String? contextPath;
  final bool returnWhenQueued;
  final bool dangerousCommandConfirmed;
  final String? triggerId;
  final AgentActionTriggerType? triggerType;
  final DateTime? scheduledAt;
  final DateTime? triggeredAt;

  /// Populated by the execution orchestrator after a Hub validate-run cache hit.
  final AgentActionPreparedExecution? cachedPreparedExecution;

  AgentActionExecutionRequest copyWith({
    String? actionId,
    AgentActionRequestSource? source,
    String? idempotencyKey,
    String? requestedBy,
    String? traceId,
    Map<String, Object?>? runtimeParameters,
    String? contextPath,
    bool? returnWhenQueued,
    bool? dangerousCommandConfirmed,
    String? triggerId,
    AgentActionTriggerType? triggerType,
    DateTime? scheduledAt,
    DateTime? triggeredAt,
    AgentActionPreparedExecution? cachedPreparedExecution,
    bool clearCachedPreparedExecution = false,
  }) {
    return AgentActionExecutionRequest(
      actionId: actionId ?? this.actionId,
      source: source ?? this.source,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      requestedBy: requestedBy ?? this.requestedBy,
      traceId: traceId ?? this.traceId,
      runtimeParameters: runtimeParameters ?? this.runtimeParameters,
      contextPath: contextPath ?? this.contextPath,
      returnWhenQueued: returnWhenQueued ?? this.returnWhenQueued,
      dangerousCommandConfirmed: dangerousCommandConfirmed ?? this.dangerousCommandConfirmed,
      triggerId: triggerId ?? this.triggerId,
      triggerType: triggerType ?? this.triggerType,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      cachedPreparedExecution: clearCachedPreparedExecution
          ? null
          : cachedPreparedExecution ?? this.cachedPreparedExecution,
    );
  }
}

class AgentActionExecution {
  const AgentActionExecution({
    required this.id,
    required this.actionId,
    required this.actionType,
    required this.status,
    required this.requestedAt,
    required this.source,
    this.idempotencyKey,
    this.requestedBy,
    this.traceId,
    this.runtimeInstanceId,
    this.runtimeSessionId,
    this.triggerId,
    this.triggerType,
    this.scheduledAt,
    this.triggeredAt,
    this.queueStartedAt,
    this.processStartedAt,
    this.finishedAt,
    this.timeoutAt,
    this.pid,
    this.exitCode,
    this.processExecutable,
    this.processArgumentCount,
    this.processCommandPreview,
    this.stdoutText,
    this.stderrText,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.stdoutStoredInChunks = false,
    this.stderrStoredInChunks = false,
    this.definitionSnapshotHash,
    this.contextHash,
    this.redactionApplied = false,
    this.failureCode,
    this.failurePhase,
    this.failureMessage,
  });

  final String id;
  final String actionId;
  final AgentActionType actionType;
  final AgentActionExecutionStatus status;
  final DateTime requestedAt;
  final AgentActionRequestSource source;
  final String? idempotencyKey;
  final String? requestedBy;
  final String? traceId;
  final String? runtimeInstanceId;
  final String? runtimeSessionId;
  final String? triggerId;
  final AgentActionTriggerType? triggerType;
  final DateTime? scheduledAt;
  final DateTime? triggeredAt;
  final DateTime? queueStartedAt;
  final DateTime? processStartedAt;
  final DateTime? finishedAt;
  final DateTime? timeoutAt;
  final int? pid;
  final int? exitCode;
  final String? processExecutable;
  final int? processArgumentCount;
  final String? processCommandPreview;
  final String? stdoutText;
  final String? stderrText;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final bool stdoutStoredInChunks;
  final bool stderrStoredInChunks;
  final String? definitionSnapshotHash;
  final String? contextHash;
  final bool redactionApplied;
  final String? failureCode;
  final String? failurePhase;
  final String? failureMessage;

  bool get isTerminal => status.isTerminal;

  bool get timedOut => status == AgentActionExecutionStatus.timedOut;

  bool get skipped => status == AgentActionExecutionStatus.skipped;

  bool get cancelled => status == AgentActionExecutionStatus.cancelled;

  bool get killed => status == AgentActionExecutionStatus.killed;

  AgentActionExecution copyWith({
    AgentActionExecutionStatus? status,
    String? idempotencyKey,
    String? requestedBy,
    String? traceId,
    String? runtimeInstanceId,
    String? runtimeSessionId,
    String? triggerId,
    AgentActionTriggerType? triggerType,
    DateTime? scheduledAt,
    DateTime? triggeredAt,
    DateTime? queueStartedAt,
    DateTime? processStartedAt,
    DateTime? finishedAt,
    DateTime? timeoutAt,
    int? pid,
    int? exitCode,
    String? processExecutable,
    int? processArgumentCount,
    String? processCommandPreview,
    String? stdoutText,
    String? stderrText,
    bool? stdoutTruncated,
    bool? stderrTruncated,
    bool? stdoutStoredInChunks,
    bool? stderrStoredInChunks,
    String? definitionSnapshotHash,
    bool? redactionApplied,
    String? contextHash,
    String? failureCode,
    String? failurePhase,
    String? failureMessage,
    bool clearStdoutText = false,
    bool clearStderrText = false,
  }) {
    return AgentActionExecution(
      id: id,
      actionId: actionId,
      actionType: actionType,
      status: status ?? this.status,
      requestedAt: requestedAt,
      source: source,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      requestedBy: requestedBy ?? this.requestedBy,
      traceId: traceId ?? this.traceId,
      runtimeInstanceId: runtimeInstanceId ?? this.runtimeInstanceId,
      runtimeSessionId: runtimeSessionId ?? this.runtimeSessionId,
      triggerId: triggerId ?? this.triggerId,
      triggerType: triggerType ?? this.triggerType,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      queueStartedAt: queueStartedAt ?? this.queueStartedAt,
      processStartedAt: processStartedAt ?? this.processStartedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      timeoutAt: timeoutAt ?? this.timeoutAt,
      pid: pid ?? this.pid,
      exitCode: exitCode ?? this.exitCode,
      processExecutable: processExecutable ?? this.processExecutable,
      processArgumentCount: processArgumentCount ?? this.processArgumentCount,
      processCommandPreview: processCommandPreview ?? this.processCommandPreview,
      stdoutText: clearStdoutText ? null : (stdoutText ?? this.stdoutText),
      stderrText: clearStderrText ? null : (stderrText ?? this.stderrText),
      stdoutTruncated: stdoutTruncated ?? this.stdoutTruncated,
      stderrTruncated: stderrTruncated ?? this.stderrTruncated,
      stdoutStoredInChunks: stdoutStoredInChunks ?? this.stdoutStoredInChunks,
      stderrStoredInChunks: stderrStoredInChunks ?? this.stderrStoredInChunks,
      definitionSnapshotHash: definitionSnapshotHash ?? this.definitionSnapshotHash,
      contextHash: contextHash ?? this.contextHash,
      redactionApplied: redactionApplied ?? this.redactionApplied,
      failureCode: failureCode ?? this.failureCode,
      failurePhase: failurePhase ?? this.failurePhase,
      failureMessage: failureMessage ?? this.failureMessage,
    );
  }
}

/// Result of a remote dry-run validation (`agent.action.validateRun`) with no side effects.
class AgentActionValidateRunSummary {
  const AgentActionValidateRunSummary({
    required this.actionId,
    required this.actionType,
    this.definitionSnapshotHash,
    this.wouldReplayExistingExecution = false,
    this.existingExecutionId,
  });

  final String actionId;
  final AgentActionType actionType;
  final String? definitionSnapshotHash;
  final bool wouldReplayExistingExecution;
  final String? existingExecutionId;

  Map<String, Object?> toRpcResultJson() {
    return <String, Object?>{
      'valid': true,
      'action_id': actionId,
      'action_type': actionType.name,
      if (definitionSnapshotHash != null) 'definition_snapshot_hash': definitionSnapshotHash,
      'would_replay_existing_execution': wouldReplayExistingExecution,
      if (existingExecutionId != null) 'existing_execution_id': existingExecutionId,
    };
  }
}
