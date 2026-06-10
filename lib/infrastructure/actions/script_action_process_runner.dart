import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_action_environment_resolver.dart';
import 'package:plug_agente/domain/actions/i_agent_operational_profile_resolver.dart';
import 'package:plug_agente/infrastructure/actions/action_process_stdin_setup.dart';
import 'package:plug_agente/infrastructure/actions/action_process_window_mode_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_prepare_execution_resolver.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_lifecycle.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_starter.dart';
import 'package:plug_agente/infrastructure/actions/script_action_adapter.dart';
import 'package:result_dart/result_dart.dart';

class ScriptActionProcessRunner implements AgentActionLocalRunner {
  ScriptActionProcessRunner({
    required AgentActionAdapterRegistry adapterRegistry,
    required IActionEnvironmentResolver environmentResolver,
    required IAgentOperationalProfileResolver operationalProfileResolver,
    required ActionProcessStdinSetup stdinSetup,
    AgentActionProcessStarter? processStarter,
    AgentActionProcessLifecycle? lifecycle,
    AgentActionRedactor redactor = const AgentActionRedactor(),
  }) : _adapterRegistry = adapterRegistry,
       _environmentResolver = environmentResolver,
       _operationalProfileResolver = operationalProfileResolver,
       _lifecycle =
           lifecycle ??
           AgentActionProcessLifecycle(
             stdinSetup: stdinSetup,
             processStarter: processStarter,
             redactor: redactor,
           );

  final AgentActionAdapterRegistry _adapterRegistry;
  final IActionEnvironmentResolver _environmentResolver;
  final IAgentOperationalProfileResolver _operationalProfileResolver;
  final AgentActionProcessLifecycle _lifecycle;

  @override
  AgentActionType get type => AgentActionType.script;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    if (definition.config is! ScriptActionConfig) {
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

    final adapterResult = _adapterRegistry.resolve(type);
    if (adapterResult.isError()) {
      return Failure(adapterResult.exceptionOrNull()!);
    }
    final adapter = adapterResult.getOrThrow();
    if (adapter is! ScriptActionAdapter) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script process runner received an invalid action adapter.',
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

    final preparedResult = await resolvePreparedExecution(
      adapter: adapter,
      definition: definition,
      request: request,
    );
    if (preparedResult.isError()) {
      return Failure(preparedResult.exceptionOrNull()!);
    }
    final prepared = preparedResult.getOrThrow();

    final invocationResult = await adapter.resolveInvocationCommand(definition);
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }

    final environmentResult = await _environmentResolver.resolveForProcess(
      definition: definition,
      request: request,
    );
    if (environmentResult.isError()) {
      return Failure(environmentResult.exceptionOrNull()!);
    }

    return _lifecycle.execute(
      executionId: executionId,
      definition: definition,
      request: request,
      invocation: invocationResult.getOrThrow(),
      workingDirectory: prepared.workingDirectory,
      contextHash: prepared.contextHash,
      processEnvironment: environmentResult.getOrThrow(),
      includeParentEnvironment: _environmentResolver.resolveIncludeParentEnvironment(
        policy: definition.policies.environment,
        operationalProfile: _operationalProfileResolver.currentProfile,
      ),
      startMode: ActionProcessWindowModeResolver.resolve(definition.policies.process.windowMode),
      failureMessages: const AgentActionProcessFailureMessages(
        processStartMessage: 'Failed to start script action process.',
        processRuntimeMessage: 'Script action process failed before completion.',
        processStartUserMessage:
            'Nao foi possivel iniciar o interpretador. Verifique o script, o interpretador e o diretorio de trabalho.',
        processRuntimeUserMessage:
            'Falha ao executar o script configurado. Verifique a configuracao da acao e tente novamente.',
        processExceptionCode: AgentActionFailureCode.interpreterNotFound,
      ),
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) {
    return _lifecycle.cancel(
      executionId: executionId,
      expectedPid: expectedPid,
      expectedProcessExecutable: expectedProcessExecutable,
      expectedProcessStartedAt: expectedProcessStartedAt,
    );
  }
}
