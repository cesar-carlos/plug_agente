import 'dart:async';
import 'dart:convert';

import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/agent_action_execution_gate_chain.dart';
import 'package:plug_agente/application/actions/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/application/actions/agent_action_failure_process_metadata.dart';
import 'package:plug_agente/application/actions/agent_action_prepared_execution_cache.dart';
import 'package:plug_agente/application/actions/agent_action_remote_lifecycle_audit_recorder.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/application/actions/elevated_agent_action_execution_service.dart';
import 'package:plug_agente/application/use_cases/notify_agent_action_execution_if_configured.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/errors/failure_extensions.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain_failures;
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

typedef AgentActionAdapterPrepareCheck =
    Future<Result<AgentActionPreparedExecution>> Function({
      required AgentActionDefinition definition,
      required AgentActionExecutionRequest request,
    });

/// Post-gate execution orchestration: queue admission, idempotency, persistence,
/// retry loop, elevated routing, and terminal metrics/audit hooks.
class AgentActionExecutionOrchestrator {
  AgentActionExecutionOrchestrator(
    this._repository,
    this._uuid, {
    ActionExecutionQueue? executionQueue,
    SaveAgentActionExecution? saveExecution,
    AgentRuntimeIdentity? runtimeIdentity,
    AgentActionExecutionMetricsCollector? metrics,
    NotifyAgentActionExecutionIfConfigured? notifyExecution,
    AgentActionSecretPlaceholderResolver? secretPlaceholderResolver,
    ElevatedAgentActionExecutionService? elevatedExecutionService,
    AgentActionRemoteLifecycleAuditRecorder? remoteLifecycleAudit,
    AgentActionRuntimeStateGuard? runtimeStateGuard,
    AgentActionPreparedExecutionCache? preparedExecutionCache,
    DateTime Function()? now,
  }) : _executionQueue = executionQueue ?? ActionExecutionQueue(),
       _saveExecution = saveExecution ?? SaveAgentActionExecution(_repository),
       _runtimeIdentity = runtimeIdentity,
       _metrics = metrics,
       _notifyExecution = notifyExecution,
       _secretPlaceholderResolver = secretPlaceholderResolver ?? const AgentActionSecretPlaceholderResolver(),
       _elevatedExecutionService = elevatedExecutionService,
       _remoteLifecycleAudit = remoteLifecycleAudit,
       _runtimeStateGuard = runtimeStateGuard,
       _preparedExecutionCache = preparedExecutionCache ?? AgentActionPreparedExecutionCache(),
       _now = now ?? DateTime.now;

  final IAgentActionRepository _repository;
  final Uuid _uuid;
  final ActionExecutionQueue _executionQueue;
  final SaveAgentActionExecution _saveExecution;
  final AgentRuntimeIdentity? _runtimeIdentity;
  final AgentActionExecutionMetricsCollector? _metrics;
  final NotifyAgentActionExecutionIfConfigured? _notifyExecution;
  final AgentActionSecretPlaceholderResolver _secretPlaceholderResolver;
  final ElevatedAgentActionExecutionService? _elevatedExecutionService;
  final AgentActionRemoteLifecycleAuditRecorder? _remoteLifecycleAudit;
  final AgentActionRuntimeStateGuard? _runtimeStateGuard;
  final AgentActionPreparedExecutionCache _preparedExecutionCache;
  final DateTime Function() _now;
  final Map<String, Future<Result<AgentActionExecution>>> _idempotentExecutions =
      <String, Future<Result<AgentActionExecution>>>{};

  Future<Result<AgentActionExecution>> run({
    required AgentActionGatedExecutionContext gatedContext,
    required AgentActionExecutionRequest request,
  }) async {
    final definition = gatedContext.definition;
    final runner = gatedContext.runner;

    final idempotencyKey = _idempotencyKeyFor(request);
    if (idempotencyKey != null) {
      final existing = _idempotentExecutions[idempotencyKey];
      if (existing != null) {
        if (request.returnWhenQueued) {
          final persistedExecutionResult = await _findPersistedIdempotentExecution(
            actionId: definition.id,
            idempotencyKey: _canonicalOptionalRequestString(request.idempotencyKey)!,
          );
          if (persistedExecutionResult.isError()) {
            return Failure(persistedExecutionResult.exceptionOrNull()!);
          }
          final persistedExecutions = persistedExecutionResult.getOrThrow();
          if (persistedExecutions.isNotEmpty) {
            return Success(persistedExecutions.first);
          }
        }
        return existing;
      }
      final persistedExecutionResult = await _findPersistedIdempotentExecution(
        actionId: definition.id,
        idempotencyKey: _canonicalOptionalRequestString(request.idempotencyKey)!,
      );
      if (persistedExecutionResult.isError()) {
        return Failure(persistedExecutionResult.exceptionOrNull()!);
      }
      final persistedExecutions = persistedExecutionResult.getOrThrow();
      if (persistedExecutions.isNotEmpty) {
        return Success(persistedExecutions.first);
      }
    }

    final startResult = await _startExecution(
      definition: definition,
      request: request,
      runner: runner,
    );
    if (startResult.isError()) {
      return Failure(startResult.exceptionOrNull()!);
    }
    final startedExecution = startResult.getOrThrow();
    if (idempotencyKey != null) {
      _idempotentExecutions[idempotencyKey] = startedExecution.completion;
      unawaited(
        startedExecution.completion.whenComplete(
          () => _idempotentExecutions.remove(idempotencyKey),
        ),
      );
    }

    if (request.returnWhenQueued) {
      unawaited(startedExecution.completion);
      return Success(startedExecution.queuedExecution);
    }

    return startedExecution.completion;
  }

  Future<Result<AgentActionValidateRunSummary>> validateRemoteAdmission({
    required AgentActionGatedExecutionContext gatedContext,
    required AgentActionExecutionRequest request,
    AgentActionAdapterPrepareCheck? adapterPrepareCheck,
  }) async {
    final definition = gatedContext.definition;

    final idempotencyKey = _idempotencyKeyFor(request);
    if (idempotencyKey != null) {
      if (_idempotentExecutions.containsKey(idempotencyKey)) {
        return Success(
          AgentActionValidateRunSummary(
            actionId: definition.id,
            actionType: definition.type,
            definitionSnapshotHash: definition.definitionSnapshotHash,
            wouldReplayExistingExecution: true,
          ),
        );
      }
      final persistedExecutionResult = await _findPersistedIdempotentExecution(
        actionId: definition.id,
        idempotencyKey: _canonicalOptionalRequestString(request.idempotencyKey)!,
      );
      if (persistedExecutionResult.isError()) {
        return Failure(persistedExecutionResult.exceptionOrNull()!);
      }
      final persistedExecutions = persistedExecutionResult.getOrThrow();
      if (persistedExecutions.isNotEmpty) {
        return Success(
          AgentActionValidateRunSummary(
            actionId: definition.id,
            actionType: definition.type,
            definitionSnapshotHash: definition.definitionSnapshotHash,
            wouldReplayExistingExecution: true,
            existingExecutionId: persistedExecutions.first.id,
          ),
        );
      }
    }

    final queueAdmission = _executionQueue.validateRemoteAdmission(
      actionId: definition.id,
      policies: definition.policies,
    );
    if (queueAdmission.isError()) {
      return Failure(queueAdmission.exceptionOrNull()!);
    }

    final prepareCheck = adapterPrepareCheck;
    if (prepareCheck != null) {
      final prepareResult = await prepareCheck(
        definition: definition,
        request: request,
      );
      if (prepareResult.isError()) {
        return Failure(prepareResult.exceptionOrNull()!);
      }
      _preparedExecutionCache.store(
        definition: definition,
        request: request,
        prepared: prepareResult.getOrThrow(),
      );
    }

    return Success(
      AgentActionValidateRunSummary(
        actionId: definition.id,
        actionType: definition.type,
        definitionSnapshotHash: definition.definitionSnapshotHash,
      ),
    );
  }

  Future<Result<List<AgentActionExecution>>> _findPersistedIdempotentExecution({
    required String actionId,
    required String idempotencyKey,
  }) async {
    final result = await _repository.listExecutions(
      actionId: actionId,
      idempotencyKey: idempotencyKey,
      limit: 1,
    );
    if (result.isError()) {
      return Failure(result.exceptionOrNull()!);
    }

    return result;
  }

  Future<Result<_StartedAgentActionExecution>> _startExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionLocalRunner runner,
  }) async {
    final requestedAt = _now();
    final persistedIdempotencyKey = _canonicalOptionalRequestString(request.idempotencyKey);
    final persistedRequestedBy = _canonicalOptionalRequestString(request.requestedBy);
    final persistedTraceId = _canonicalOptionalRequestString(request.traceId);
    final persistedTriggerId = _canonicalOptionalRequestString(request.triggerId);
    final identity = _runtimeIdentity;
    final queuedExecution = AgentActionExecution(
      id: _uuid.v4(),
      actionId: definition.id,
      actionType: definition.type,
      status: AgentActionExecutionStatus.queued,
      requestedAt: requestedAt,
      source: request.source,
      idempotencyKey: persistedIdempotencyKey,
      requestedBy: persistedRequestedBy,
      traceId: persistedTraceId,
      runtimeInstanceId: identity?.runtimeInstanceId,
      runtimeSessionId: identity?.runtimeSessionId,
      triggerId: persistedTriggerId,
      triggerType: request.triggerType,
      scheduledAt: request.scheduledAt,
      triggeredAt: request.triggeredAt,
      queueStartedAt: requestedAt,
      definitionSnapshotHash: definition.definitionSnapshotHash,
    );
    final initialSaveResult = await _saveExecution(queuedExecution);
    if (initialSaveResult.isError()) {
      return Failure(initialSaveResult.exceptionOrNull()!);
    }

    await _remoteLifecycleAudit?.recordEnqueued(queuedExecution);

    final completion = _observeQueueCompletion(
      queuedExecution: queuedExecution,
      queuedResult: _executionQueue.enqueue(
        AgentActionQueueRequest<AgentActionExecution>(
          actionId: definition.id,
          executionId: queuedExecution.id,
          idempotencyKey: persistedIdempotencyKey,
          policies: definition.policies,
          task: () => _runPersistedExecution(
            queuedExecution: queuedExecution,
            definition: definition,
            request: request,
            runner: runner,
          ),
        ),
      ),
    );

    return Success(
      _StartedAgentActionExecution(
        queuedExecution: queuedExecution,
        completion: completion,
      ),
    );
  }

  Future<Result<AgentActionExecution>> _observeQueueCompletion({
    required AgentActionExecution queuedExecution,
    required Future<Result<AgentActionExecution>> queuedResult,
  }) async {
    final result = await queuedResult;
    if (result.isSuccess()) {
      return result;
    }

    final actionFailure = _toActionFailure(result.exceptionOrNull()!);
    final rejectedExecution = queuedExecution.copyWith(
      status: _queuedFailureStatus(actionFailure),
      finishedAt: _now(),
      redactionApplied: true,
      failureCode: actionFailure.code,
      failurePhase: _failurePhaseForFailure(actionFailure),
      failureMessage: actionFailure.message,
    );
    final rejectedSaveResult = await _saveExecution(rejectedExecution);
    if (rejectedSaveResult.isError()) {
      return Failure(rejectedSaveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(rejectedExecution);
    await _remoteLifecycleAudit?.recordFinished(
      execution: rejectedExecution,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    );
    return Failure(actionFailure);
  }

  AgentActionExecutionStatus _queuedFailureStatus(ActionFailure actionFailure) {
    return switch (actionFailure.code) {
      AgentActionFailureCode.queueCancelled => AgentActionExecutionStatus.cancelled,
      AgentActionFailureCode.queueIgnored => AgentActionExecutionStatus.skipped,
      _ => AgentActionExecutionStatus.failed,
    };
  }

  String? _idempotencyKeyFor(AgentActionExecutionRequest request) {
    final idempotencyKey = _canonicalOptionalRequestString(request.idempotencyKey);
    if (idempotencyKey == null) {
      return null;
    }

    return '${request.actionId.trim()}:$idempotencyKey';
  }

  String? _canonicalOptionalRequestString(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  AgentActionExecutionRequest _executionRequestWithPreparedCache({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) {
    final cachedPrepared = _preparedExecutionCache.consumeIfValid(
      definition: definition,
      request: request,
    );
    if (cachedPrepared == null) {
      return request;
    }

    return request.copyWith(cachedPreparedExecution: cachedPrepared);
  }

  Future<Result<AgentActionProcessResult>> _runElevatedExecution({
    required String executionId,
    required AgentActionDefinition definition,
  }) async {
    final service = _elevatedExecutionService;
    if (service == null) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Elevated execution service is not configured.',
          code: AgentActionFailureCode.elevatedNotConfigured,
          context: {
            'execution_id': executionId,
            'phase': AgentActionProcessConstants.elevatedSubmitPhase,
            'reason': AgentActionGateConstants.elevatedNotConfiguredReason,
            'user_message': 'The elevated execution service is not available on this agent.',
          },
        ),
      );
    }

    return service.run(
      executionId: executionId,
      definition: definition,
    );
  }

  Future<Result<AgentActionExecution>> _runPersistedExecution({
    required AgentActionExecution queuedExecution,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionLocalRunner runner,
  }) async {
    final initialGuardCheck = _runtimeStateGuard?.ensureCanAcceptExecution(
      request: request,
      actionType: definition.type,
    );
    if (initialGuardCheck != null && initialGuardCheck.isError()) {
      return Failure(initialGuardCheck.exceptionOrNull()!);
    }

    var runningExecution = queuedExecution.copyWith(
      status: AgentActionExecutionStatus.running,
      processStartedAt: _now(),
    );
    final runningSaveResult = await _saveExecution(runningExecution);
    if (runningSaveResult.isError()) {
      return Failure(runningSaveResult.exceptionOrNull()!);
    }

    await _remoteLifecycleAudit?.recordStarted(runningExecution);

    final retryPolicy = definition.policies.retry;
    final maxAttempts = retryPolicy.effectiveMaxAttempts(
      request,
      runElevated: definition.policies.elevated.runElevated,
    );
    var terminalExecution = runningExecution;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (attempt > 1) {
        if (retryPolicy.delayBetweenAttempts > Duration.zero) {
          await Future<void>.delayed(retryPolicy.delayBetweenAttempts);
        }
        final guardCheck = _runtimeStateGuard?.ensureCanAcceptExecution(
          request: request,
          actionType: definition.type,
        );
        if (guardCheck != null && guardCheck.isError()) {
          return Failure(guardCheck.exceptionOrNull()!);
        }
        runningExecution = runningExecution.copyWith(
          status: AgentActionExecutionStatus.running,
          processStartedAt: _now(),
        );
        final retryRunningSave = await _saveExecution(runningExecution);
        if (retryRunningSave.isError()) {
          return Failure(retryRunningSave.exceptionOrNull()!);
        }
      }

      final resolvedDefinitionResult = await _secretPlaceholderResolver.resolveForExecution(
        definition,
      );
      if (resolvedDefinitionResult.isError()) {
        return Failure(resolvedDefinitionResult.exceptionOrNull()!);
      }

      final resolvedDefinition = resolvedDefinitionResult.getOrThrow();
      final executionRequest = _executionRequestWithPreparedCache(
        definition: resolvedDefinition,
        request: request,
      );
      final runResult = resolvedDefinition.policies.elevated.runElevated
          ? await _runElevatedExecution(
              executionId: runningExecution.id,
              definition: resolvedDefinition,
            )
          : await runner.run(
              executionId: runningExecution.id,
              definition: resolvedDefinition,
              request: executionRequest,
            );
      terminalExecution = runResult.fold(
        (output) => _executionFromOutput(runningExecution, output),
        (failure) => _failedExecutionFromFailure(
          runningExecution,
          failure,
        ),
      );

      if (terminalExecution.status.isSuccess ||
          !retryPolicy.isRetriableStatus(terminalExecution.status) ||
          attempt >= maxAttempts) {
        break;
      }
    }

    return _finalizeTerminalExecution(
      definition: definition,
      terminalExecution: terminalExecution,
    );
  }

  Future<Result<AgentActionExecution>> _finalizeTerminalExecution({
    required AgentActionDefinition definition,
    required AgentActionExecution terminalExecution,
  }) async {
    final terminalSaveResult = await _saveExecution(terminalExecution);
    if (terminalSaveResult.isError()) {
      return Failure(terminalSaveResult.exceptionOrNull()!);
    }

    _recordTerminalExecutionMetrics(terminalExecution);
    await _remoteLifecycleAudit?.recordFinished(
      execution: terminalExecution,
      rpcMethod: AgentActionRpcConstants.agentActionRunRpcMethodName,
    );
    final notify = _notifyExecution;
    if (notify != null) {
      await notify(
        definition: definition,
        execution: terminalExecution,
      );
    }

    return terminalSaveResult;
  }

  void _recordTerminalExecutionMetrics(AgentActionExecution execution) {
    final metrics = _metrics;
    if (metrics == null || !execution.isTerminal) {
      return;
    }

    metrics.recordTerminalOutcome(execution.status);
    metrics.recordCapturedOutputPersisted(
      stdoutCaptured: execution.stdoutText != null,
      stderrCaptured: execution.stderrText != null,
      stdoutTruncated: execution.stdoutTruncated,
      stderrTruncated: execution.stderrTruncated,
      stdoutUtf8Bytes: _utf8ByteLength(execution.stdoutText),
      stderrUtf8Bytes: _utf8ByteLength(execution.stderrText),
    );
    final finishedAt = execution.finishedAt;
    if (finishedAt == null) {
      return;
    }

    final startedAt = execution.processStartedAt ?? execution.queueStartedAt ?? execution.requestedAt;
    metrics.recordExecutionDuration(finishedAt.difference(startedAt));
  }

  AgentActionExecution _failedExecutionFromFailure(
    AgentActionExecution runningExecution,
    Exception failure,
  ) {
    final actionFailure = _toActionFailure(failure);
    final processMetadata = AgentActionFailureProcessMetadata.fromFailureContext(
      actionFailure.context,
    );
    return runningExecution.copyWith(
      status: AgentActionExecutionStatus.failed,
      finishedAt: _now(),
      redactionApplied: true,
      failureCode: actionFailure.code,
      failurePhase: _failurePhaseForFailure(actionFailure),
      failureMessage: actionFailure.message,
      processExecutable: processMetadata.processExecutable ?? runningExecution.processExecutable,
      processArgumentCount: processMetadata.processArgumentCount ?? runningExecution.processArgumentCount,
      processCommandPreview: processMetadata.processCommandPreview ?? runningExecution.processCommandPreview,
    );
  }

  ActionFailure _toActionFailure(Exception failure) {
    if (failure is ActionFailure) {
      return failure;
    }
    if (failure is domain_failures.Failure) {
      return _actionFailureFromDomainFailure(failure);
    }

    return _actionFailureFromDomainFailure(
      domain_failures.ServerFailure.withContext(
        message: 'An unexpected error occurred.',
        cause: failure,
        context: {
          'operation': 'agent_action_execution',
          'technical_message': failure.toString(),
        },
      ),
    );
  }

  ActionFailure _actionFailureFromDomainFailure(domain_failures.Failure failure) {
    final message = failure.toUserMessage();
    final context = {
      ...failure.context,
      if (!failure.context.containsKey('technical_message')) 'technical_message': _technicalDetailFor(failure),
    };

    return switch (failure) {
      domain_failures.ValidationFailure() => ActionValidationFailure.withContext(
        message: message,
        code: failure.code,
        cause: failure.cause,
        timestamp: failure.timestamp,
        context: context,
      ),
      _ => ActionRuntimeFailure.withContext(
        message: message,
        code: failure.code,
        cause: failure.cause,
        timestamp: failure.timestamp,
        context: context,
      ),
    };
  }

  String _technicalDetailFor(domain_failures.Failure failure) {
    final cause = failure.cause;
    if (cause != null) {
      return cause.toString();
    }
    return failure.message;
  }

  AgentActionExecution _executionFromOutput(
    AgentActionExecution initialExecution,
    AgentActionProcessResult output,
  ) {
    return initialExecution.copyWith(
      status: output.status,
      processStartedAt: output.processStartedAt,
      finishedAt: output.finishedAt,
      timeoutAt: output.timedOut ? output.finishedAt : null,
      pid: output.pid,
      exitCode: output.exitCode,
      processExecutable: output.processExecutable,
      processArgumentCount: output.processArgumentCount,
      processCommandPreview: output.processCommandPreview,
      stdoutText: output.stdout.isCaptured ? output.stdout.text : null,
      stderrText: output.stderr.isCaptured ? output.stderr.text : null,
      stdoutTruncated: output.stdout.isTruncated,
      stderrTruncated: output.stderr.isTruncated,
      contextHash: output.contextHash,
      redactionApplied: output.redactionApplied,
      failureCode: _failureCodeFor(output),
      failurePhase: _failurePhaseFor(output),
      failureMessage: _failureMessageFor(output),
    );
  }

  String? _failureCodeFor(AgentActionProcessResult output) {
    if (output.status == AgentActionExecutionStatus.succeeded) {
      return null;
    }

    final elevatedFailureCode = output.failureCode?.trim();
    if (elevatedFailureCode != null && elevatedFailureCode.isNotEmpty) {
      return elevatedFailureCode;
    }

    return switch (output.status) {
      AgentActionExecutionStatus.timedOut => AgentActionFailureCode.executionTimedOut,
      AgentActionExecutionStatus.killed => AgentActionFailureCode.executionKilled,
      AgentActionExecutionStatus.failed => AgentActionFailureCode.exitCodeRejected,
      AgentActionExecutionStatus.unknown => AgentActionFailureCode.runtimeUnknown,
      _ => AgentActionFailureCode.runtimeError,
    };
  }

  String? _failureMessageFor(AgentActionProcessResult output) {
    if (output.status == AgentActionExecutionStatus.succeeded) {
      return null;
    }

    final elevatedFailureMessage = output.failureMessage?.trim();
    if (elevatedFailureMessage != null && elevatedFailureMessage.isNotEmpty) {
      return elevatedFailureMessage;
    }

    return switch (output.status) {
      AgentActionExecutionStatus.timedOut => 'Command exceeded the maximum execution time.',
      AgentActionExecutionStatus.killed => 'Main process was terminated.',
      AgentActionExecutionStatus.failed => 'Command exited with code ${output.exitCode}.',
      AgentActionExecutionStatus.unknown => 'Command ended without a known exit code.',
      _ => 'Failed to execute action.',
    };
  }

  String? _failurePhaseFor(AgentActionProcessResult output) {
    return switch (output.status) {
      AgentActionExecutionStatus.succeeded => null,
      AgentActionExecutionStatus.timedOut => 'timeout',
      AgentActionExecutionStatus.killed => 'cancel',
      AgentActionExecutionStatus.failed => 'process_exit',
      AgentActionExecutionStatus.unknown => 'process_runtime',
      _ => 'process_runtime',
    };
  }

  String? _failurePhaseForFailure(ActionFailure failure) {
    final contextPhase = failure.context['phase'];
    if (contextPhase is String && contextPhase.trim().isNotEmpty) {
      return contextPhase;
    }

    return switch (failure.code) {
      AgentActionFailureCode.elevatedSubmitFailed ||
      AgentActionFailureCode.elevatedNotConfigured ||
      AgentActionFailureCode.elevatedRequestProtectionFailed => AgentActionProcessConstants.elevatedSubmitPhase,
      _ => switch (failure) {
        ActionQueueFailure() => 'queue',
        ActionTimeoutFailure() => 'timeout',
        ActionAuthorizationFailure() => 'authorization',
        ActionValidationFailure() => 'validation',
        ActionRuntimeFailure() => 'process_runtime',
        ActionNotFoundFailure() => 'lookup',
        _ => null,
      },
    };
  }

  int _utf8ByteLength(String? text) {
    if (text == null) {
      return 0;
    }
    return utf8.encode(text).length;
  }
}

class _StartedAgentActionExecution {
  const _StartedAgentActionExecution({
    required this.queuedExecution,
    required this.completion,
  });

  final AgentActionExecution queuedExecution;
  final Future<Result<AgentActionExecution>> completion;
}
