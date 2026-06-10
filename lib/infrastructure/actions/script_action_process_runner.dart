import 'dart:async';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_action_environment_resolver.dart';
import 'package:plug_agente/domain/actions/i_agent_operational_profile_resolver.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/action_process_window_mode_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_kill_guard.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/script_action_adapter.dart';
import 'package:result_dart/result_dart.dart';

class ScriptActionProcessRunner implements AgentActionLocalRunner {
  ScriptActionProcessRunner({
    required IActionEnvironmentResolver environmentResolver, required IAgentOperationalProfileResolver operationalProfileResolver, required ActionProcessStdinSetup stdinSetup, AgentActionProcessStarter? processStarter,
    ActionCommandNormalizer? commandNormalizer,
    ActionPathValidator? pathValidator,
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _processStarter = processStarter ?? Process.start,
       _commandNormalizer = commandNormalizer ?? const ActionCommandNormalizer(),
       _pathValidator = pathValidator ?? ActionPathValidator(),
       _environmentResolver = environmentResolver,
       _operationalProfileResolver = operationalProfileResolver,
       _stdinSetup = stdinSetup,
       _redactor = redactor;

  final AgentActionProcessStarter _processStarter;
  final ActionCommandNormalizer _commandNormalizer;
  final ActionPathValidator _pathValidator;
  final IActionEnvironmentResolver _environmentResolver;
  final IAgentOperationalProfileResolver _operationalProfileResolver;
  final ActionProcessStdinSetup _stdinSetup;
  final AgentActionRedactor _redactor;
  final Map<String, Process> _activeProcessesByExecutionId = <String, Process>{};
  final Set<String> _killedExecutionIds = <String>{};

  @override
  AgentActionType get type => AgentActionType.script;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final config = definition.config;
    if (config is! ScriptActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script process runner received an invalid action config.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'phase': AgentActionProcessConstants.executionPreflightPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de script e invalida.',
          },
        ),
      );
    }

    final adapter = ScriptActionAdapter(
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

    final contextPathResult = await _pathValidator.validateContextFile(
      actionId: definition.id,
      contextPath: request.contextPath,
      policy: definition.policies.context,
      pathPolicy: definition.policies.path,
    );
    if (contextPathResult.isError()) {
      return Failure(contextPathResult.exceptionOrNull()!);
    }

    final invocationResult = await adapter.resolveInvocationCommand(definition);
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }
    final invocation = invocationResult.getOrThrow();
    final workingDirectory = workingDirectoryResult.getOrThrow().path?.canonicalPath;
    final contextHash = contextPathResult.getOrThrow().path?.contentHash;

    final environmentResult = await _environmentResolver.resolveForProcess(
      definition: definition,
      request: request,
    );
    if (environmentResult.isError()) {
      return Failure(environmentResult.exceptionOrNull()!);
    }
    final processEnvironment = environmentResult.getOrThrow();
    final includeParentEnvironment = _environmentResolver.resolveIncludeParentEnvironment(
      policy: definition.policies.environment,
      operationalProfile: _operationalProfileResolver.currentProfile,
    );
    final startMode = ActionProcessWindowModeResolver.resolve(definition.policies.process.windowMode);

    try {
      final startedAt = DateTime.now();
      final process = await _processStarter(
        invocation.executable,
        invocation.arguments,
        workingDirectory: workingDirectory,
        environment: processEnvironment.isEmpty ? null : processEnvironment,
        includeParentEnvironment: includeParentEnvironment,
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
          message: 'Failed to start script action process.',
          cause: error,
          code: AgentActionFailureCode.interpreterNotFound,
          context: {
            'action_id': definition.id,
            ...AgentActionProcessInvocationDiagnostics.forInvocation(
              invocation: invocation,
              capturePolicy: definition.policies.capture,
            ),
            'phase': 'start_process',
            'reason': AgentActionProcessConstants.processStartFailedReason,
            'user_message':
                'Nao foi possivel iniciar o interpretador. Verifique o script, o interpretador e o diretorio de trabalho.',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Script action process failed before completion.',
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
                'Falha ao executar o script configurado. Verifique a configuracao da acao e tente novamente.',
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
