import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_com_object_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_prepare_execution_resolver.dart';
import 'package:plug_agente/infrastructure/actions/com_object_action_adapter.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_handler.dart';
import 'package:plug_agente/infrastructure/actions/com_object_invocation_registry.dart';
import 'package:result_dart/result_dart.dart';

class ComObjectActionRunner implements AgentActionLocalRunner {
  ComObjectActionRunner({
    required ComObjectInvocationRegistry invocationRegistry,
    ActionPathValidator? pathValidator,
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _invocationRegistry = invocationRegistry,
       _pathValidator = pathValidator ?? ActionPathValidator(),
       _redactor = redactor;

  final ComObjectInvocationRegistry _invocationRegistry;
  final ActionPathValidator _pathValidator;
  final AgentActionRedactor _redactor;

  @override
  AgentActionType get type => AgentActionType.comObject;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    if (!Platform.isWindows) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'COM object actions are only supported on Windows.',
          code: AgentActionFailureCode.runtimeError,
          context: {
            'action_id': definition.id,
            'execution_id': executionId,
            'phase': 'platform_check',
            'reason': AgentActionComObjectConstants.unsupportedPlatformReason,
            'user_message': 'Acoes COM so podem ser executadas no Windows.',
          },
        ),
      );
    }

    final config = definition.config;
    if (config is! ComObjectActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'COM object runner received an invalid action config.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'phase': AgentActionProcessConstants.executionPreflightPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao COM e invalida.',
          },
        ),
      );
    }

    final adapter = ComObjectActionAdapter(
      invocationRegistry: _invocationRegistry,
      pathValidator: _pathValidator,
    );
    final preparedResult = await resolvePreparedExecution(
      adapter: adapter,
      definition: definition,
      request: request,
    );
    if (preparedResult.isError()) {
      return Failure(preparedResult.exceptionOrNull()!);
    }

    final handlerResult = _invocationRegistry.resolve(
      progId: config.progId,
      memberName: config.memberName,
    );
    if (handlerResult.isError()) {
      return Failure(handlerResult.exceptionOrNull()!);
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

    final startedAt = DateTime.now();
    final maxRuntime = definition.policies.timeout.maxRuntime;
    final invocationFuture = handlerResult.getOrThrow().invoke(
      arguments: config.arguments,
    );

    final Result<ComObjectInvocationResult> invocationResult;
    try {
      invocationResult = maxRuntime > Duration.zero
          ? await invocationFuture.timeout(maxRuntime)
          : await invocationFuture;
    } on TimeoutException {
      // COM handlers nao expoem processo principal cancelavel: a politica
      // `killMainProcessOnTimeout` nao se aplica aqui. Apenas relatamos o
      // timeout como falha terminal.
      return Failure(
        ActionTimeoutFailure.withContext(
          message: 'COM object invocation exceeded the configured timeout.',
          code: AgentActionFailureCode.executionTimedOut,
          context: {
            'action_id': definition.id,
            'execution_id': executionId,
            'phase': 'execution',
            'reason': AgentActionComObjectConstants.invocationTimedOutReason,
            'timeout_ms': maxRuntime.inMilliseconds,
            'user_message': 'A invocacao COM excedeu o tempo limite configurado.',
          },
        ),
      );
    }

    final finishedAt = DateTime.now();
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }

    final output = invocationResult.getOrThrow();
    final stdoutText = _redactor.redactText(
      jsonEncode(<String, Object?>{
        'summary': output.summary,
        'details': output.details,
      }),
    );

    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 0,
        exitCode: 0,
        processStartedAt: startedAt,
        finishedAt: finishedAt,
        processExecutable: 'com-object',
        processArgumentCount: config.arguments.length,
        processCommandPreview: preparedResult.getOrThrow().redactedCommandPreview,
        stdout: definition.policies.capture.captureStdout
            ? AgentActionCapturedOutput(
                text: stdoutText,
                isCaptured: true,
              )
            : AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        contextHash: contextPathResult.getOrThrow().path?.contentHash,
        redactionApplied: true,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Failure(
      ActionNotFoundFailure.withContext(
        message: 'COM object execution is not cancellable after invocation starts.',
        code: AgentActionFailureCode.processNotActive,
        context: {
          'execution_id': executionId,
          'expected_pid': expectedPid,
          'phase': 'cancel',
          'reason': AgentActionProcessConstants.processNotActiveReason,
          'user_message': 'Acoes COM nao possuem processo ativo para cancelamento.',
        },
      ),
    );
  }
}
