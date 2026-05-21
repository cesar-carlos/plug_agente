import 'dart:async';
import 'dart:io';

import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_executable_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/action_process_window_mode_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_kill_guard.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/executable_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

class ExecutableActionProcessRunner implements AgentActionLocalRunner {
  ExecutableActionProcessRunner({
    AgentActionProcessStarter? processStarter,
    ActionCommandNormalizer commandNormalizer = const ActionCommandNormalizer(),
    ActionPathValidator? pathValidator,
    ActionEnvironmentResolver? environmentResolver,
    ActionProcessStdinSetup? stdinSetup,
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _processStarter = processStarter ?? Process.start,
       _commandNormalizer = commandNormalizer,
       _pathValidator = pathValidator ?? ActionPathValidator(),
       _environmentResolver = environmentResolver ?? const ActionEnvironmentResolver(),
       _stdinSetup = stdinSetup ?? const ActionProcessStdinSetup(),
       _redactor = redactor;

  final AgentActionProcessStarter _processStarter;
  final ActionCommandNormalizer _commandNormalizer;
  final ActionPathValidator _pathValidator;
  final ActionEnvironmentResolver _environmentResolver;
  final ActionProcessStdinSetup _stdinSetup;
  final AgentActionRedactor _redactor;
  final Map<String, Process> _activeProcessesByExecutionId = <String, Process>{};
  final Set<String> _killedExecutionIds = <String>{};

  @override
  AgentActionType get type => AgentActionType.executable;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final config = definition.config;
    if (config is! ExecutableActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Executable process runner received an invalid action config.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'phase': AgentActionProcessConstants.executionPreflightPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao executavel e invalida.',
          },
        ),
      );
    }

    final adapter = ExecutableActionAdapter(
      commandNormalizer: _commandNormalizer,
      pathValidator: _pathValidator,
    );
    final preparedResult = await adapter.prepareExecution(
      definition: definition,
      request: request,
    );
    if (preparedResult.isError()) {
      return Failure(preparedResult.exceptionOrNull()!);
    }

    final workingDirectoryResult = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
      phase: 'execution_preflight',
    );
    if (workingDirectoryResult.isError()) {
      return Failure(workingDirectoryResult.exceptionOrNull()!);
    }
    final workingDirectorySnapshotResult = _pathValidator.guardPathSnapshot(
      actionId: definition.id,
      field: 'workingDirectory',
      savedReference: config.workingDirectory,
      currentPath: workingDirectoryResult.getOrThrow().path,
    );
    if (workingDirectorySnapshotResult.isError()) {
      return Failure(workingDirectorySnapshotResult.exceptionOrNull()!);
    }

    final contextPathResult = await _pathValidator.validateContextFile(
      actionId: definition.id,
      contextPath: request.contextPath,
      policy: definition.policies.context,
      pathPolicy: definition.policies.path,
    );
    if (contextPathResult.isError()) {
      return Failure(contextPathResult.exceptionOrNull()!);
    }

    final executableValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'executablePath',
      path: config.executablePath,
      allowedExtensions: AgentActionExecutableConstants.allowedExecutableExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      phase: AgentActionProcessConstants.executionPreflightPhase,
      requireLaunchAccess: WindowsExecutableLaunchAccessChecker.shouldValidateLaunchAccessForPath(
        phase: AgentActionProcessConstants.executionPreflightPhase,
        path: config.executablePath.displayPath,
      ),
    );
    if (executableValidation.isError()) {
      return Failure(executableValidation.exceptionOrNull()!);
    }

    final workingDirectory = workingDirectoryResult.getOrThrow().path?.canonicalPath;
    final contextHash = contextPathResult.getOrThrow().path?.contentHash;
    final invocationResult = _commandNormalizer.normalizeExecutable(
      actionId: definition.id,
      executableCanonicalPath: executableValidation.getOrThrow().path!.canonicalPath,
      arguments: config.arguments,
      phase: 'execution_preflight',
    );
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }
    final invocation = invocationResult.getOrThrow();

    final environmentResult = await _environmentResolver.resolveForProcess(
      definition: definition,
      request: request,
    );
    if (environmentResult.isError()) {
      return Failure(environmentResult.exceptionOrNull()!);
    }
    final processEnvironment = environmentResult.getOrThrow();
    final startMode = ActionProcessWindowModeResolver.resolve(definition.policies.process.windowMode);

    try {
      final startedAt = DateTime.now();
      final process = await _processStarter(
        invocation.executable,
        invocation.arguments,
        workingDirectory: workingDirectory,
        environment: processEnvironment.isEmpty ? null : processEnvironment,
        includeParentEnvironment: true,
        runInShell: invocation.runInShell,
        mode: startMode,
      );
      _activeProcessesByExecutionId[executionId] = process;
      final stdinSetupResult = await _stdinSetup.configure(
        process: process,
        definition: definition,
        request: request,
        actionId: definition.id,
        diagnostics: AgentActionProcessInvocationDiagnostics.forInvocation(
          invocation: invocation,
          capturePolicy: definition.policies.capture,
        ),
      );
      if (stdinSetupResult.isError()) {
        return Failure(stdinSetupResult.exceptionOrNull()!);
      }

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
      final stdout = await stdoutFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const AgentActionCapturedOutput(
          text: '',
          isCaptured: true,
          isTruncated: true,
        ),
      );
      final stderr = await stderrFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () => const AgentActionCapturedOutput(
          text: '',
          isCaptured: true,
          isTruncated: true,
        ),
      );

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
    } on ProcessException catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to start executable action process.',
          cause: error,
          context: {
            'action_id': definition.id,
            ...AgentActionProcessInvocationDiagnostics.forInvocation(
              invocation: invocation,
              capturePolicy: definition.policies.capture,
            ),
            'phase': 'start_process',
            'reason': AgentActionProcessConstants.processStartFailedReason,
            'user_message':
                'Nao foi possivel iniciar o executavel. Verifique o caminho, os argumentos e o diretorio de trabalho.',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Executable action process failed before completion.',
          cause: error,
          context: {
            'action_id': definition.id,
            ...AgentActionProcessInvocationDiagnostics.forInvocation(
              invocation: invocation,
              capturePolicy: definition.policies.capture,
            ),
            'phase': 'process_runtime',
            'reason': AgentActionProcessConstants.processRuntimeErrorReason,
            'user_message':
                'Falha ao executar o processo configurado. Verifique a configuracao da acao e tente novamente.',
          },
        ),
      );
    } finally {
      _activeProcessesByExecutionId.remove(executionId);
      _killedExecutionIds.remove(executionId);
    }
  }

  @override
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

  Future<int?> _waitExitCodeAfterTimeout(Process process) {
    return process.exitCode
        .then<int?>((value) => value)
        .timeout(
          const Duration(seconds: 5),
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
