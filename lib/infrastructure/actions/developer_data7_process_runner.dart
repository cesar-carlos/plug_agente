import 'dart:async';
import 'dart:io';

import 'package:plug_agente/application/actions/action_environment_resolver.dart';
import 'package:plug_agente/application/actions/agent_operational_profile_resolver.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_process_output_capture.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_kill_guard.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_killer.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_definition_resolver.dart';
import 'package:result_dart/result_dart.dart';

typedef DeveloperData7ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment,
      bool runInShell,
      ProcessStartMode mode,
    });

class DeveloperData7ProcessRunner implements AgentActionLocalRunner {
  DeveloperData7ProcessRunner({
    DeveloperData7DefinitionResolver? definitionResolver,
    DeveloperData7ProcessStarter? processStarter,
    ActionEnvironmentResolver? environmentResolver,
    AgentOperationalProfileResolver? operationalProfileResolver,
    ActionProcessStdinSetup? stdinSetup,
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _definitionResolver = definitionResolver ?? DeveloperData7DefinitionResolver(),
       _processStarter = processStarter ?? Process.start,
       _environmentResolver = environmentResolver ?? const ActionEnvironmentResolver(),
       _operationalProfileResolver = operationalProfileResolver ?? const AgentOperationalProfileResolver(),
       _stdinSetup = stdinSetup ?? const ActionProcessStdinSetup(),
       _redactor = redactor;

  final DeveloperData7DefinitionResolver _definitionResolver;
  final DeveloperData7ProcessStarter _processStarter;
  final ActionEnvironmentResolver _environmentResolver;
  final AgentOperationalProfileResolver _operationalProfileResolver;
  final ActionProcessStdinSetup _stdinSetup;
  final AgentActionRedactor _redactor;
  final Map<String, Process> _activeProcessesByExecutionId = <String, Process>{};
  final Set<String> _killedExecutionIds = <String>{};

  @override
  AgentActionType get type => AgentActionType.developer;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final preparedResult = await _definitionResolver.prepareExecution(
      definition: definition,
      request: request,
    );
    if (preparedResult.isError()) {
      return Failure(preparedResult.exceptionOrNull()!);
    }
    final prepared = preparedResult.getOrThrow();

    final includeParentEnvironment = _environmentResolver.resolveIncludeParentEnvironment(
      policy: definition.policies.environment,
      operationalProfile: _operationalProfileResolver.currentProfile,
    );

    try {
      final startedAt = DateTime.now();
      final process = await _processStarter(
        prepared.command.executable,
        prepared.command.arguments,
        workingDirectory: prepared.command.workingDirectory,
        includeParentEnvironment: includeParentEnvironment,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );
      _activeProcessesByExecutionId[executionId] = process;

      final stdinSetupResult = await _stdinSetup.configure(
        process: process,
        definition: definition,
        request: request,
        actionId: definition.id,
        diagnostics: <String, Object?>{
          'executable': prepared.command.executable,
          'argument_count': prepared.command.arguments.length,
          'command_preview': AgentActionProcessInvocationDiagnostics.logSafeCommandPreviewText(
            preview: prepared.command.redactedPreview,
            capturePolicy: definition.policies.capture,
          ),
        },
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
          processExecutable: prepared.command.executable,
          processArgumentCount: prepared.command.arguments.length,
          processCommandPreview: AgentActionProcessInvocationDiagnostics.logSafeCommandPreviewText(
            preview: prepared.command.redactedPreview,
            capturePolicy: definition.policies.capture,
          ),
          stdout: stdout,
          stderr: stderr,
          redactionApplied: definition.policies.capture.redactBeforePersisting,
          timedOut: timedOut,
          killed: killed,
        ),
      );
    } on ProcessException catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Failed to start Developer Data7 process.',
          cause: error,
          context: {
            'action_id': definition.id,
            ...prepared.redactedDiagnostics,
            'phase': 'start_process',
            'reason': AgentActionProcessConstants.processStartFailedReason,
            'executable': prepared.command.executable,
            'argument_count': prepared.command.arguments.length,
            'command_preview': AgentActionProcessInvocationDiagnostics.logSafeCommandPreviewText(
              preview: prepared.command.redactedPreview,
              capturePolicy: definition.policies.capture,
            ),
            'user_message': 'Nao foi possivel iniciar o Executor.exe. Verifique o caminho do executavel e do projeto.',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Developer Data7 process failed before completion.',
          cause: error,
          context: {
            'action_id': definition.id,
            ...prepared.redactedDiagnostics,
            'phase': 'process_runtime',
            'reason': AgentActionProcessConstants.processRuntimeErrorReason,
            'executable': prepared.command.executable,
            'argument_count': prepared.command.arguments.length,
            'command_preview': AgentActionProcessInvocationDiagnostics.logSafeCommandPreviewText(
              preview: prepared.command.redactedPreview,
              capturePolicy: definition.policies.capture,
            ),
            'user_message': 'Falha ao executar o projeto Data7. Revise a configuracao da acao e tente novamente.',
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
