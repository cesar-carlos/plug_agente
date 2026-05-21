import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
import 'package:plug_agente/application/actions/elevated_action_execution_abort_registry.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_elevated_action_execution_canceller.dart';
import 'package:result_dart/result_dart.dart';

class CancelAgentActionExecution {
  CancelAgentActionExecution(
    this._repository,
    this._runnerRegistry, {
    ActionExecutionQueue? executionQueue,
    SaveAgentActionExecution? saveExecution,
    AgentActionExecutionMetricsCollector? metrics,
    IElevatedActionExecutionCanceller? elevatedCanceller,
    ElevatedActionExecutionAbortRegistry? elevatedAbortRegistry,
    AgentActionRemoteLifecycleAuditRecorder? remoteLifecycleAudit,
    DateTime Function()? now,
  }) : _executionQueue = executionQueue ?? ActionExecutionQueue(),
       _saveExecution = saveExecution ?? SaveAgentActionExecution(_repository),
       _metrics = metrics,
       _elevatedCanceller = elevatedCanceller,
       _elevatedAbortRegistry = elevatedAbortRegistry,
       _remoteLifecycleAudit = remoteLifecycleAudit,
       _now = now ?? DateTime.now;

  final IAgentActionRepository _repository;
  final AgentActionLocalRunnerRegistry _runnerRegistry;
  final ActionExecutionQueue _executionQueue;
  final SaveAgentActionExecution _saveExecution;
  final AgentActionExecutionMetricsCollector? _metrics;
  final IElevatedActionExecutionCanceller? _elevatedCanceller;
  final ElevatedActionExecutionAbortRegistry? _elevatedAbortRegistry;
  final AgentActionRemoteLifecycleAuditRecorder? _remoteLifecycleAudit;
  final DateTime Function() _now;

  Future<Result<AgentActionExecution>> call(String executionId) async {
    final trimmedExecutionId = executionId.trim();
    if (trimmedExecutionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Execution id is required to cancel an action.',
          context: const {
            'field': 'executionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe a execucao que sera cancelada.',
          },
        ),
      );
    }

    final executionResult = await _repository.getExecution(trimmedExecutionId);
    if (executionResult.isError()) {
      return Failure(executionResult.exceptionOrNull()!);
    }
    final execution = executionResult.getOrThrow();
    if (execution.isTerminal) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Action execution is already finished.',
          code: AgentActionFailureCode.alreadyFinished,
          context: {
            'execution_id': execution.id,
            'status': execution.status.name,
            'reason': AgentActionRpcConstants.agentActionCancelAlreadyFinishedErrorReason,
            'user_message': 'A execucao ja terminou e nao pode mais ser cancelada.',
          },
        ),
      );
    }
    await _remoteLifecycleAudit?.recordCancelRequested(execution);

    if (execution.status == AgentActionExecutionStatus.queued) {
      return _cancelQueued(execution);
    }
    if (execution.status != AgentActionExecutionStatus.running) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Action execution is not running.',
          code: AgentActionFailureCode.cancelNotRunning,
          context: {
            'execution_id': execution.id,
            'status': execution.status.name,
            'reason': AgentActionRpcConstants.agentActionCancelNotRunningContextReason,
            'user_message': 'A execucao ainda nao possui processo ativo para finalizar.',
          },
        ),
      );
    }

    final elevatedCancelResult = await _cancelRunningElevatedIfNeeded(execution);
    if (elevatedCancelResult != null) {
      return elevatedCancelResult;
    }

    final runnerResult = _runnerRegistry.resolve(execution.actionType);
    if (runnerResult.isError()) {
      return Failure(runnerResult.exceptionOrNull()!);
    }

    final cancelResult = await runnerResult.getOrThrow().cancel(
      executionId: execution.id,
      expectedPid: execution.pid,
      expectedProcessExecutable: execution.processExecutable,
      expectedProcessStartedAt: execution.processStartedAt,
    );
    if (cancelResult.isError()) {
      _recordCancelFailureMetrics(cancelResult.exceptionOrNull()!);
      return Failure(cancelResult.exceptionOrNull()!);
    }

    final cancellation = cancelResult.getOrThrow();
    final updatedExecution = execution.copyWith(
      status: cancellation.status,
      finishedAt: _now(),
      pid: cancellation.pid,
      redactionApplied: true,
      failureCode: cancellation.killed
          ? AgentActionFailureCode.executionKilled
          : AgentActionFailureCode.executionCancelled,
      failurePhase: 'cancel',
      failureMessage: cancellation.message ?? 'Execucao cancelada.',
    );
    final saveResult = await _saveExecution(updatedExecution);
    if (saveResult.isError()) {
      return Failure(saveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(updatedExecution);
    await _recordRemoteLifecycleFinished(updatedExecution);
    return saveResult;
  }

  Future<Result<AgentActionExecution>?> _cancelRunningElevatedIfNeeded(
    AgentActionExecution execution,
  ) async {
    if (!await _isElevatedRunningExecution(execution)) {
      return null;
    }

    final canceller = _elevatedCanceller;
    if (canceller == null) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated execution canceller is not configured.',
          context: {
            'execution_id': execution.id,
            'user_message': 'O cancelamento de execucoes elevadas nao esta disponivel neste agente.',
          },
        ),
      );
    }

    _elevatedAbortRegistry?.requestAbort(execution.id);
    final cancelResult = await canceller.cancel(executionId: execution.id);
    if (cancelResult.isError()) {
      return Failure(cancelResult.exceptionOrNull()!);
    }

    final cancellation = cancelResult.getOrThrow();
    final updatedExecution = execution.copyWith(
      status: cancellation.status,
      finishedAt: _now(),
      pid: cancellation.pid,
      redactionApplied: true,
      failureCode: cancellation.killed
          ? AgentActionFailureCode.executionKilled
          : AgentActionFailureCode.executionCancelled,
      failurePhase: 'cancel',
      failureMessage: cancellation.message ?? 'Execucao cancelada.',
    );
    final saveResult = await _saveExecution(updatedExecution);
    if (saveResult.isError()) {
      return Failure(saveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(updatedExecution);
    await _recordRemoteLifecycleFinished(updatedExecution);
    return saveResult;
  }

  Future<bool> _isElevatedRunningExecution(AgentActionExecution execution) async {
    final definitionResult = await _repository.getDefinition(execution.actionId);
    if (definitionResult.isSuccess()) {
      return definitionResult.getOrThrow().policies.elevated.runElevated;
    }

    final pid = execution.pid;
    return pid == null || pid == 0;
  }

  Future<Result<AgentActionExecution>> _cancelQueued(
    AgentActionExecution execution,
  ) async {
    final cancelResult = _executionQueue.cancelQueued(executionId: execution.id);
    if (cancelResult.isError()) {
      return Failure(cancelResult.exceptionOrNull()!);
    }

    final cancellation = cancelResult.getOrThrow();
    final updatedExecution = execution.copyWith(
      status: cancellation.status,
      finishedAt: _now(),
      redactionApplied: true,
      failureCode: AgentActionFailureCode.queueCancelled,
      failurePhase: 'queue',
      failureMessage: cancellation.message ?? 'Execucao cancelada antes de iniciar.',
    );
    final saveResult = await _saveExecution(updatedExecution);
    if (saveResult.isError()) {
      return Failure(saveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(updatedExecution);
    await _recordRemoteLifecycleFinished(updatedExecution);
    return saveResult;
  }

  Future<void> _recordRemoteLifecycleFinished(AgentActionExecution execution) async {
    await _remoteLifecycleAudit?.recordFinished(
      execution: execution,
      rpcMethod: AgentActionRpcConstants.agentActionCancelRpcMethodName,
    );
  }

  void _recordCancelFailureMetrics(Exception failure) {
    final metrics = _metrics;
    if (metrics == null || failure is! ActionFailure) {
      return;
    }

    switch (failure.code) {
      case AgentActionFailureCode.killFailed:
        metrics.recordCancelKillFailed();
      case AgentActionFailureCode.killPermissionDenied:
        metrics.recordCancelKillPermissionDenied();
      case AgentActionFailureCode.processNotActive:
        metrics.recordCancelProcessNotActive();
      case AgentActionFailureCode.processIdMismatch:
        metrics.recordCancelProcessIdMismatch();
      case AgentActionFailureCode.processIdentityMismatch:
        metrics.recordCancelProcessIdentityMismatch();
      case AgentActionFailureCode.processIdentityUnavailable:
        metrics.recordCancelProcessIdentityUnavailable();
      default:
        break;
    }
  }

  void _recordTerminalExecutionMetrics(AgentActionExecution execution) {
    final metrics = _metrics;
    if (metrics == null || !execution.isTerminal) {
      return;
    }

    metrics.recordTerminalOutcome(execution.status);
    final finishedAt = execution.finishedAt;
    if (finishedAt == null) {
      return;
    }

    final startedAt = execution.processStartedAt ?? execution.queueStartedAt ?? execution.requestedAt;
    metrics.recordExecutionDuration(finishedAt.difference(startedAt));
  }
}
