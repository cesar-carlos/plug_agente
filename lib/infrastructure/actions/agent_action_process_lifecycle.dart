import 'dart:async';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/agent_action_execution_metrics_collector.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_failure_cause.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_kill_guard.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionProcessFailureMessages {
  const AgentActionProcessFailureMessages({
    required this.processStartMessage,
    required this.processRuntimeMessage,
    required this.processStartUserMessage,
    required this.processRuntimeUserMessage,
    this.processExceptionCode,
  });

  final String processStartMessage;
  final String processRuntimeMessage;
  final String processStartUserMessage;
  final String processRuntimeUserMessage;
  final String? processExceptionCode;
}

class AgentActionProcessLifecycle {
  AgentActionProcessLifecycle({
    required ActionProcessStdinSetup stdinSetup,
    AgentActionProcessStarter? processStarter,
    AgentActionRedactor redactor = const AgentActionRedactor(),
    Duration outputCaptureDrainTimeout = const Duration(seconds: 5),
    DateTime Function()? now,
    AgentActionProcessTreeController? processTreeController,
    AgentActionExecutionMetricsCollector? metrics,
  }) : _stdinSetup = stdinSetup,
       _processStarter = processStarter ?? Process.start,
       _redactor = redactor,
       _outputCaptureDrainTimeout = outputCaptureDrainTimeout,
       _now = now ?? DateTime.now,
       _processTreeController = processTreeController ?? WindowsJobObjectProcessTreeController(),
       _metrics = metrics;

  final ActionProcessStdinSetup _stdinSetup;
  final AgentActionProcessStarter _processStarter;
  final AgentActionRedactor _redactor;
  final Duration _outputCaptureDrainTimeout;
  final DateTime Function() _now;
  final AgentActionProcessTreeController _processTreeController;
  final AgentActionExecutionMetricsCollector? _metrics;
  final Map<String, _ActiveProcess> _activeProcessesByExecutionId = <String, _ActiveProcess>{};
  final Set<String> _killedExecutionIds = <String>{};

  Future<Result<AgentActionProcessResult>> execute({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
    required AgentActionCommandInvocation invocation,
    required String? workingDirectory,
    required String? contextHash,
    required Map<String, String> processEnvironment,
    required bool includeParentEnvironment,
    required ProcessStartMode startMode,
    required AgentActionProcessFailureMessages failureMessages,
  }) async {
    final effectiveInvocation = invocation;
    AgentActionProcessTreeLease? processTreeLease;
    try {
      final startedAt = _now();
      final deadline = startedAt.add(definition.policies.timeout.maxRuntime);
      late final Process process;
      try {
        process = await _startBeforeDeadline(
          deadline: deadline,
          executable: effectiveInvocation.executable,
          arguments: effectiveInvocation.arguments,
          workingDirectory: workingDirectory,
          environment: processEnvironment.isEmpty ? null : processEnvironment,
          includeParentEnvironment: includeParentEnvironment,
          runInShell: effectiveInvocation.runInShell,
          mode: startMode,
        );
      } on TimeoutException catch (error) {
        _metrics?.recordProcessTimeout();
        return Failure(
          _timeoutFailure(
            definition: definition,
            phase: 'start_process',
            cause: error,
            failureMessages: failureMessages,
          ),
        );
      } on Exception catch (error) {
        _metrics?.recordProcessSpawnFailure();
        return Failure(
          ActionRuntimeFailure.withContext(
            message: failureMessages.processStartMessage,
            cause: AgentActionProcessFailureCause.fromException(
              phase: 'start_process',
              error: error,
            ),
            code: failureMessages.processExceptionCode,
            context: {
              'action_id': definition.id,
              ...AgentActionProcessInvocationDiagnostics.forInvocation(
                invocation: effectiveInvocation,
                capturePolicy: definition.policies.capture,
              ),
              'phase': 'start_process',
              'reason': AgentActionProcessConstants.processStartFailedReason,
              'user_message': failureMessages.processStartUserMessage,
            },
          ),
        );
      }

      final treeResult = await _processTreeController.attach(process);
      if (treeResult.isError()) {
        _metrics?.recordProcessTreeAttachFailure();
        process.kill();
        return Failure(treeResult.exceptionOrNull()!);
      }
      processTreeLease = treeResult.getOrThrow();
      _metrics?.recordProcessStarted(_now().difference(startedAt));
      _activeProcessesByExecutionId[executionId] = _ActiveProcess(process, processTreeLease);
      final stdoutFuture = ActionProcessOutputCapture.capture(
        process.stdout,
        isEnabled: definition.policies.capture.captureStdout,
        maxBytes: definition.policies.capture.maxCapturedOutputBytes,
        encoding: definition.policies.encoding.stdout,
        redactor: _redactor,
        redactBeforePersisting: definition.policies.capture.redactBeforePersisting,
      );
      final stderrFuture = ActionProcessOutputCapture.capture(
        process.stderr,
        isEnabled: definition.policies.capture.captureStderr,
        maxBytes: definition.policies.capture.maxCapturedOutputBytes,
        encoding: definition.policies.encoding.stderr,
        redactor: _redactor,
        redactBeforePersisting: definition.policies.capture.redactBeforePersisting,
      );

      final diagnostics = AgentActionProcessInvocationDiagnostics.forInvocation(
        invocation: effectiveInvocation,
        capturePolicy: definition.policies.capture,
      );
      final stdinSetupResult = await _stdinSetup.configure(
        process: process,
        definition: definition,
        request: request,
        actionId: definition.id,
        diagnostics: diagnostics,
        ioTimeout: _remainingUntil(deadline),
      );
      if (stdinSetupResult.isError()) {
        await _abortStartedProcess(
          process: process,
          processTreeLease: processTreeLease,
          stdoutFuture: stdoutFuture,
          stderrFuture: stderrFuture,
        );
        return Failure(stdinSetupResult.exceptionOrNull()!);
      }

      var timedOut = false;
      var killed = false;
      final executionTimeout = _remainingUntil(deadline);
      if (executionTimeout <= Duration.zero) {
        timedOut = true;
      }
      final exitCode = await process.exitCode
          .then<int?>((value) => value)
          .timeout(
            executionTimeout <= Duration.zero ? Duration.zero : executionTimeout,
            onTimeout: () async {
              timedOut = true;
              _metrics?.recordProcessTimeout();
              if (definition.policies.timeout.killMainProcessOnTimeout) {
                killed = await _terminateProcessTree(process, processTreeLease!);
                if (killed) {
                  _killedExecutionIds.add(executionId);
                }
                // The deadline belongs to the whole operation. Do not add an
                // arbitrary second wait after requesting termination.
                return null;
              }

              // The operator explicitly chose not to kill the process. Keep
              // the registry entry until it actually exits so cancellation and
              // retry admission cannot lose ownership or start a duplicate.
              return process.exitCode.then<int?>((value) => value);
            },
          );

      final finishedAt = _now();
      final drainTimeout = timedOut && killed ? Duration.zero : _boundedDrainTimeout(deadline);
      final stdout = await _awaitCapturedOutput(stdoutFuture, timeout: drainTimeout);
      final stderr = await _awaitCapturedOutput(stderrFuture, timeout: drainTimeout);

      return Success(
        AgentActionProcessResult(
          status: _statusFor(
            definition: definition,
            executionId: executionId,
            exitCode: exitCode,
            timedOut: timedOut,
            killed: killed,
          ),
          pid: process.pid,
          exitCode: exitCode,
          processStartedAt: startedAt,
          finishedAt: finishedAt,
          processExecutable: effectiveInvocation.executable,
          processArgumentCount: effectiveInvocation.arguments.length,
          processCommandPreview: AgentActionProcessInvocationDiagnostics.logSafeCommandPreview(
            invocation: effectiveInvocation,
            capturePolicy: definition.policies.capture,
          ),
          stdout: stdout,
          stderr: stderr,
          contextHash: contextHash,
          timedOut: timedOut,
          killed: killed,
          redactionApplied: definition.policies.capture.redactBeforePersisting,
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: failureMessages.processRuntimeMessage,
          cause: AgentActionProcessFailureCause.fromException(
            phase: 'process_runtime',
            error: error,
          ),
          context: {
            'action_id': definition.id,
            ...AgentActionProcessInvocationDiagnostics.forInvocation(
              invocation: effectiveInvocation,
              capturePolicy: definition.policies.capture,
            ),
            'phase': 'process_runtime',
            'reason': AgentActionProcessConstants.processRuntimeErrorReason,
            'user_message': failureMessages.processRuntimeUserMessage,
          },
        ),
      );
    } finally {
      _activeProcessesByExecutionId.remove(executionId);
      _killedExecutionIds.remove(executionId);
      if (processTreeLease != null) {
        await _processTreeController.release(processTreeLease);
      }
    }
  }

  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    final activeProcess = _activeProcessesByExecutionId[executionId];
    if (activeProcess == null) {
      return Failure(
        ActionNotFoundFailure.withContext(
          message: 'Action execution process is not active.',
          code: AgentActionFailureCode.processNotActive,
          context: {
            'execution_id': executionId,
            'reason': AgentActionProcessConstants.processNotActiveReason,
            'user_message': 'Nao existe processo ativo para esta execucao.',
          },
        ),
      );
    }

    final validationFailure = AgentActionProcessKillGuard.validateBeforeKill(
      executionId: executionId,
      process: activeProcess.process,
      expectedPid: expectedPid,
      expectedProcessExecutable: expectedProcessExecutable,
      expectedProcessStartedAt: expectedProcessStartedAt,
    );
    if (validationFailure != null) {
      return Failure(validationFailure);
    }

    final terminated = await _terminateProcessTree(activeProcess.process, activeProcess.treeLease);
    if (!terminated) {
      final killFailure = AgentActionProcessKiller.killMainProcess(
        executionId: executionId,
        process: activeProcess.process,
      );
      if (killFailure != null) return Failure(killFailure);
    }

    _killedExecutionIds.add(executionId);
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: activeProcess.process.pid,
        message: activeProcess.treeLease.supportsTreeTermination
            ? 'Arvore de processos finalizada.'
            : 'Processo principal finalizado.',
      ),
    );
  }

  Future<void> _abortStartedProcess({
    required Process process,
    required AgentActionProcessTreeLease processTreeLease,
    required Future<AgentActionCapturedOutput> stdoutFuture,
    required Future<AgentActionCapturedOutput> stderrFuture,
  }) async {
    await _terminateProcessTree(process, processTreeLease);
    await _drainOutputCaptures(stdoutFuture, stderrFuture);
  }

  Future<void> _drainOutputCaptures(
    Future<AgentActionCapturedOutput> stdoutFuture,
    Future<AgentActionCapturedOutput> stderrFuture,
  ) async {
    await Future.wait(<Future<AgentActionCapturedOutput>>[
      stdoutFuture.timeout(
        _outputCaptureDrainTimeout,
        onTimeout: () => const AgentActionCapturedOutput(
          text: '',
          isCaptured: true,
          isTruncated: true,
        ),
      ),
      stderrFuture.timeout(
        _outputCaptureDrainTimeout,
        onTimeout: () => const AgentActionCapturedOutput(
          text: '',
          isCaptured: true,
          isTruncated: true,
        ),
      ),
    ]);
  }

  Future<AgentActionCapturedOutput> _awaitCapturedOutput(
    Future<AgentActionCapturedOutput> captureFuture, {
    required Duration timeout,
  }) {
    return captureFuture.timeout(
      timeout,
      onTimeout: () => const AgentActionCapturedOutput(
        text: '',
        isCaptured: true,
        isTruncated: true,
      ),
    );
  }

  Future<Process> _startBeforeDeadline({
    required DateTime deadline,
    required String executable,
    required List<String> arguments,
    required String? workingDirectory,
    required Map<String, String>? environment,
    required bool includeParentEnvironment,
    required bool runInShell,
    required ProcessStartMode mode,
  }) async {
    final remaining = _remainingUntil(deadline);
    if (remaining <= Duration.zero) {
      throw TimeoutException('Process start deadline elapsed.');
    }

    final start = _processStarter(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      mode: mode,
    );
    return start.timeout(
      remaining,
      onTimeout: () {
        // If the OS creates the process after the Dart future timed out, stop
        // it immediately instead of leaving an untracked child behind.
        unawaited(
          start
              .then<void>((process) {
                process.kill();
              })
              .catchError((_) {}),
        );
        throw TimeoutException('Process start deadline elapsed.');
      },
    );
  }

  Future<bool> _terminateProcessTree(Process process, AgentActionProcessTreeLease lease) async {
    if (lease.supportsTreeTermination) {
      final result = await _processTreeController.terminate(lease);
      if (result.isSuccess()) {
        _metrics?.recordProcessTreeTermination();
        return true;
      }
      return false;
    }
    return process.kill();
  }

  Duration _remainingUntil(DateTime deadline) {
    final remaining = deadline.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  Duration _boundedDrainTimeout(DateTime deadline) {
    final remaining = _remainingUntil(deadline);
    return remaining < _outputCaptureDrainTimeout ? remaining : _outputCaptureDrainTimeout;
  }

  ActionTimeoutFailure _timeoutFailure({
    required AgentActionDefinition definition,
    required String phase,
    required TimeoutException cause,
    required AgentActionProcessFailureMessages failureMessages,
  }) {
    return ActionTimeoutFailure.withContext(
      message: failureMessages.processRuntimeMessage,
      cause: AgentActionProcessFailureCause.fromException(phase: phase, error: cause),
      code: AgentActionFailureCode.executionTimedOut,
      context: {
        'action_id': definition.id,
        'phase': phase,
        'reason': AgentActionProcessConstants.processRuntimeErrorReason,
        'user_message': failureMessages.processRuntimeUserMessage,
      },
    );
  }

  AgentActionExecutionStatus _statusFor({
    required AgentActionDefinition definition,
    required String executionId,
    required int? exitCode,
    required bool timedOut,
    required bool killed,
  }) {
    if (timedOut && definition.policies.timeout.killMainProcessOnTimeout) {
      return AgentActionExecutionStatus.timedOut;
    }
    if (killed || _killedExecutionIds.contains(executionId)) {
      return AgentActionExecutionStatus.killed;
    }
    if (timedOut) {
      return AgentActionExecutionStatus.failed;
    }
    if (exitCode == null) {
      return AgentActionExecutionStatus.unknown;
    }
    if (definition.policies.exitCode.isAccepted(exitCode)) {
      return AgentActionExecutionStatus.succeeded;
    }

    return AgentActionExecutionStatus.failed;
  }
}

final class _ActiveProcess {
  const _ActiveProcess(this.process, this.treeLease);
  final Process process;
  final AgentActionProcessTreeLease treeLease;
}
