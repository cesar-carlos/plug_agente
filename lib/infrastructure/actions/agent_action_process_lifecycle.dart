import 'dart:async';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_kill_guard.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
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
    Duration exitCodeAfterTimeoutWait = const Duration(seconds: 5),
  }) : _stdinSetup = stdinSetup,
       _processStarter = processStarter ?? Process.start,
       _redactor = redactor,
       _outputCaptureDrainTimeout = outputCaptureDrainTimeout,
       _exitCodeAfterTimeoutWait = exitCodeAfterTimeoutWait;

  final ActionProcessStdinSetup _stdinSetup;
  final AgentActionProcessStarter _processStarter;
  final AgentActionRedactor _redactor;
  final Duration _outputCaptureDrainTimeout;
  final Duration _exitCodeAfterTimeoutWait;
  final Map<String, Process> _activeProcessesByExecutionId = <String, Process>{};
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
    try {
      final startedAt = DateTime.now();
      late final Process process;
      try {
        process = await _processStarter(
          invocation.executable,
          invocation.arguments,
          workingDirectory: workingDirectory,
          environment: processEnvironment.isEmpty ? null : processEnvironment,
          includeParentEnvironment: includeParentEnvironment,
          runInShell: invocation.runInShell,
          mode: startMode,
        );
      } on ProcessException catch (error) {
        return Failure(
          ActionRuntimeFailure.withContext(
            message: failureMessages.processStartMessage,
            cause: error,
            code: failureMessages.processExceptionCode,
            context: {
              'action_id': definition.id,
              ...AgentActionProcessInvocationDiagnostics.forInvocation(
                invocation: invocation,
                capturePolicy: definition.policies.capture,
              ),
              'phase': 'start_process',
              'reason': AgentActionProcessConstants.processStartFailedReason,
              'user_message': failureMessages.processStartUserMessage,
            },
          ),
        );
      }

      _activeProcessesByExecutionId[executionId] = process;
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
        invocation: invocation,
        capturePolicy: definition.policies.capture,
      );
      final stdinSetupResult = await _stdinSetup.configure(
        process: process,
        definition: definition,
        request: request,
        actionId: definition.id,
        diagnostics: diagnostics,
      );
      if (stdinSetupResult.isError()) {
        await _abortStartedProcess(
          process: process,
          stdoutFuture: stdoutFuture,
          stderrFuture: stderrFuture,
        );
        return Failure(stdinSetupResult.exceptionOrNull()!);
      }

      var timedOut = false;
      var killed = false;
      final exitCode = await process.exitCode
          .then<int?>((value) => value)
          .timeout(
            definition.policies.timeout.maxRuntime,
            onTimeout: () async {
              timedOut = true;
              if (definition.policies.timeout.killMainProcessOnTimeout) {
                killed = process.kill();
                if (killed) {
                  _killedExecutionIds.add(executionId);
                }
              }

              return _waitExitCodeAfterTimeout(process);
            },
          );

      final finishedAt = DateTime.now();
      final stdout = await _awaitCapturedOutput(stdoutFuture);
      final stderr = await _awaitCapturedOutput(stderrFuture);

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
          processExecutable: invocation.executable,
          processArgumentCount: invocation.arguments.length,
          processCommandPreview: AgentActionProcessInvocationDiagnostics.logSafeCommandPreview(
            invocation: invocation,
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
          cause: error,
          context: {
            'action_id': definition.id,
            ...AgentActionProcessInvocationDiagnostics.forInvocation(
              invocation: invocation,
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
    }
  }

  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    final process = _activeProcessesByExecutionId[executionId];
    if (process == null) {
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
      process: process,
      expectedPid: expectedPid,
      expectedProcessExecutable: expectedProcessExecutable,
      expectedProcessStartedAt: expectedProcessStartedAt,
    );
    if (validationFailure != null) {
      return Failure(validationFailure);
    }

    final killFailure = AgentActionProcessKiller.killMainProcess(
      executionId: executionId,
      process: process,
    );
    if (killFailure != null) {
      return Failure(killFailure);
    }

    _killedExecutionIds.add(executionId);
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
        pid: process.pid,
        message: 'Processo principal finalizado.',
      ),
    );
  }

  Future<void> _abortStartedProcess({
    required Process process,
    required Future<AgentActionCapturedOutput> stdoutFuture,
    required Future<AgentActionCapturedOutput> stderrFuture,
  }) async {
    process.kill();
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
    Future<AgentActionCapturedOutput> captureFuture,
  ) {
    return captureFuture.timeout(
      _outputCaptureDrainTimeout,
      onTimeout: () => const AgentActionCapturedOutput(
        text: '',
        isCaptured: true,
        isTruncated: true,
      ),
    );
  }

  Future<int?> _waitExitCodeAfterTimeout(Process process) {
    return process.exitCode
        .then<int?>((value) => value)
        .timeout(
          _exitCodeAfterTimeoutWait,
          onTimeout: () => null,
        );
  }

  AgentActionExecutionStatus _statusFor({
    required AgentActionDefinition definition,
    required String executionId,
    required int? exitCode,
    required bool timedOut,
    required bool killed,
  }) {
    if (timedOut) {
      if (definition.policies.timeout.killMainProcessOnTimeout) {
        return AgentActionExecutionStatus.timedOut;
      }
      return AgentActionExecutionStatus.failed;
    }
    if (killed || _killedExecutionIds.contains(executionId)) {
      return AgentActionExecutionStatus.killed;
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
