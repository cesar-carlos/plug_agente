import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_output_pager.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';

String cancelReasonForRpcSnapshot(AgentActionExecution execution) {
  if (execution.killed) {
    return AgentActionRpcConstants.agentActionCancelResultReasonKilled;
  }
  if (execution.cancelled) {
    return AgentActionRpcConstants.agentActionCancelResultReasonCancelled;
  }
  return AgentActionRpcConstants.agentActionCancelResultReasonCancelRequested;
}

Map<String, dynamic> agentActionExecutionToGetExecutionResult(
  AgentActionExecution execution, {
  AgentActionExecutionOutputPaging paging = const AgentActionExecutionOutputPaging(),
  bool exposeStdout = true,
  bool exposeStderr = true,
  bool sanitizeForRemoteHub = false,
  CapturedOutputUtf8Window? stdoutWindow,
  CapturedOutputUtf8Window? stderrWindow,
}) {
  final allowSensitiveFields = !sanitizeForRemoteHub || execution.redactionApplied;
  final trigger = _triggerBlock(execution);
  final timestamps = _timestampsBlock(execution);
  final process = _processBlock(execution, includeCommandPreview: allowSensitiveFields);
  final stdoutCaptured = execution.stdoutStoredInChunks || execution.stdoutText != null;
  final stdoutMap = exposeStdout && allowSensitiveFields
      ? buildCapturedOutputRpcMap(
          captured: stdoutCaptured,
          storageTruncated: execution.stdoutTruncated,
          fullText: execution.stdoutText,
          offsetUtf8: paging.stdoutOffsetUtf8,
          maxBytes: paging.maxOutputBytesPerStream,
          precomputedWindow: stdoutWindow,
        )
      : buildCapturedOutputRpcMap(
          captured: false,
          storageTruncated: false,
          fullText: null,
          offsetUtf8: 0,
          maxBytes: paging.maxOutputBytesPerStream,
        );
  final stderrCaptured = execution.stderrStoredInChunks || execution.stderrText != null;
  final stderrMap = exposeStderr && allowSensitiveFields
      ? buildCapturedOutputRpcMap(
          captured: stderrCaptured,
          storageTruncated: execution.stderrTruncated,
          fullText: execution.stderrText,
          offsetUtf8: paging.stderrOffsetUtf8,
          maxBytes: paging.maxOutputBytesPerStream,
          precomputedWindow: stderrWindow,
        )
      : buildCapturedOutputRpcMap(
          captured: false,
          storageTruncated: false,
          fullText: null,
          offsetUtf8: 0,
          maxBytes: paging.maxOutputBytesPerStream,
        );
  final failure = _failureBlock(execution);

  return <String, dynamic>{
    'execution_id': execution.id,
    'action_id': execution.actionId,
    'action_type': execution.actionType.name,
    'status': execution.status.name,
    'source': execution.source.name,
    'requested_at': execution.requestedAt.toUtc().toIso8601String(),
    if (execution.idempotencyKey != null && execution.idempotencyKey!.trim().isNotEmpty)
      'idempotency_key': execution.idempotencyKey!.trim(),
    if (execution.requestedBy != null && execution.requestedBy!.trim().isNotEmpty)
      'requested_by': execution.requestedBy!.trim(),
    if (execution.traceId != null && execution.traceId!.trim().isNotEmpty) 'trace_id': execution.traceId!.trim(),
    if (execution.runtimeInstanceId != null && execution.runtimeInstanceId!.trim().isNotEmpty)
      'runtime_instance_id': execution.runtimeInstanceId!.trim(),
    if (execution.runtimeSessionId != null && execution.runtimeSessionId!.trim().isNotEmpty)
      'runtime_session_id': execution.runtimeSessionId!.trim(),
    'trigger': ?trigger,
    'timestamps': timestamps,
    'process': process,
    'output': <String, dynamic>{
      'stdout': stdoutMap,
      'stderr': stderrMap,
    },
    'flags': <String, dynamic>{
      'terminal': execution.isTerminal,
      'skipped': execution.skipped,
      'timed_out': execution.timedOut,
      'cancelled': execution.cancelled,
      'killed': execution.killed,
      'redaction_applied': execution.redactionApplied,
    },
    if (execution.contextHash != null && execution.contextHash!.trim().isNotEmpty)
      'context_hash': execution.contextHash!.trim(),
    if (execution.definitionSnapshotHash != null && execution.definitionSnapshotHash!.trim().isNotEmpty)
      'definition_snapshot_hash': execution.definitionSnapshotHash!.trim(),
    'failure': ?failure,
  };
}

Map<String, dynamic> agentActionCancelToRpcResult(
  AgentActionExecution execution, {
  required bool cancelled,
  bool sanitizeForRemoteHub = true,
}) {
  return <String, dynamic>{
    'cancelled': cancelled,
    'execution_id': execution.id,
    'status': execution.status.name,
    'reason': cancelReasonForRpcSnapshot(execution),
    'execution': agentActionExecutionToGetExecutionResult(
      execution,
      sanitizeForRemoteHub: sanitizeForRemoteHub,
    ),
  };
}

Map<String, dynamic>? _triggerBlock(AgentActionExecution execution) {
  final hasTriggerId = execution.triggerId != null && execution.triggerId!.trim().isNotEmpty;
  final hasType = execution.triggerType != null;
  final hasScheduled = execution.scheduledAt != null;
  final hasTriggered = execution.triggeredAt != null;
  if (!hasTriggerId && !hasType && !hasScheduled && !hasTriggered) {
    return null;
  }
  return <String, dynamic>{
    if (hasTriggerId) 'trigger_id': execution.triggerId!.trim(),
    if (hasType) 'trigger_type': execution.triggerType!.name,
    if (hasScheduled) 'scheduled_at': execution.scheduledAt!.toUtc().toIso8601String(),
    if (hasTriggered) 'triggered_at': execution.triggeredAt!.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _timestampsBlock(AgentActionExecution execution) {
  return <String, dynamic>{
    if (execution.queueStartedAt != null) 'queue_started_at': execution.queueStartedAt!.toUtc().toIso8601String(),
    if (execution.processStartedAt != null) 'process_started_at': execution.processStartedAt!.toUtc().toIso8601String(),
    if (execution.finishedAt != null) 'finished_at': execution.finishedAt!.toUtc().toIso8601String(),
    if (execution.timeoutAt != null) 'timeout_at': execution.timeoutAt!.toUtc().toIso8601String(),
  };
}

Map<String, dynamic> _processBlock(
  AgentActionExecution execution, {
  bool includeCommandPreview = true,
}) {
  final map = <String, dynamic>{};
  if (execution.pid != null) {
    map['pid'] = execution.pid;
  }
  if (execution.exitCode != null) {
    map['exit_code'] = execution.exitCode;
  }
  if (execution.processExecutable != null && execution.processExecutable!.trim().isNotEmpty) {
    map['executable'] = execution.processExecutable!.trim();
  }
  if (execution.processArgumentCount != null) {
    map['argument_count'] = execution.processArgumentCount;
  }
  if (includeCommandPreview &&
      execution.processCommandPreview != null &&
      execution.processCommandPreview!.trim().isNotEmpty) {
    map['command_preview'] = execution.processCommandPreview!.trim();
  }
  return map;
}

Map<String, dynamic>? _failureBlock(AgentActionExecution execution) {
  final code = execution.failureCode?.trim();
  final message = execution.failureMessage?.trim();
  final phase = execution.failurePhase?.trim();
  if ((code == null || code.isEmpty) && (message == null || message.isEmpty) && (phase == null || phase.isEmpty)) {
    return null;
  }

  final correctiveAction = const AgentActionFailureDiagnosticsResolver().resolve(execution).correctiveAction?.wireValue;

  return <String, dynamic>{
    if (code != null && code.isNotEmpty) 'code': code,
    if (phase != null && phase.isNotEmpty) 'phase': phase,
    if (correctiveAction != null && correctiveAction.isNotEmpty) 'corrective_action': correctiveAction,
    if (message != null && message.isNotEmpty) 'message': message,
  };
}
