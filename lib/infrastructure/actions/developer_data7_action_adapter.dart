import 'dart:io';

import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_definition_resolver.dart';
import 'package:plug_agente/infrastructure/actions/developer_executor_command_builder.dart';
import 'package:result_dart/result_dart.dart';

class DeveloperData7ActionAdapter implements AgentActionAdapter {
  DeveloperData7ActionAdapter({
    DeveloperData7DefinitionResolver? definitionResolver,
    DeveloperExecutorCommandBuilder commandBuilder = const DeveloperExecutorCommandBuilder(),
  }) : _definitionResolver = definitionResolver ?? DeveloperData7DefinitionResolver(),
       _commandBuilder = commandBuilder;

  final DeveloperData7DefinitionResolver _definitionResolver;
  final DeveloperExecutorCommandBuilder _commandBuilder;

  @override
  AgentActionType get type => AgentActionType.developer;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _definitionResolver.resolveDefinition(
      definition: definition,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();

    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
        safeMessage: definition.canRun
            ? 'Developer Data7 action is ready to run.'
            : 'Developer Data7 action is valid but not active.',
        redactedDiagnostics: {
          'engine': resolved.normalizedConfig.engine.name,
          'connection_label': resolved.connection.label,
          'catalog_connection_count': resolved.catalogConnectionCount,
          'used_default_config_path': resolved.usedDefaultConfigPath,
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _definitionResolver.resolveDefinition(
      definition: definition,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }

    return Success(
      definition.copyWith(
        config: resolvedResult.getOrThrow().normalizedConfig,
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
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

    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: prepared.command.redactedPreview,
        workingDirectory: prepared.command.workingDirectory,
        redactedDiagnostics: prepared.redactedDiagnostics,
      ),
    );
  }

  Future<Result<AgentActionCommandInvocation>> resolveInvocationCommand(
    AgentActionDefinition definition, {
    String phase = 'execution_preflight',
  }) async {
    final resolvedResult = await _definitionResolver.resolveDefinition(
      definition: definition,
      phase: phase,
      compareSavedSnapshots: true,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();
    final command = _commandBuilder.build(
      executorPath: resolved.executorPath.canonicalPath,
      projectPath: resolved.projectPath.canonicalPath,
      connectionId: resolved.connection.id,
      workingDirectory: resolved.workingDirectory,
    );

    return Success(
      AgentActionCommandInvocation(
        executable: command.executable,
        arguments: command.arguments,
        runInShell: false,
        mode: ProcessStartMode.normal,
        redactedPreview: command.redactedPreview,
        normalizedCommandLength: command.arguments.fold<int>(
          command.executable.length,
          (length, argument) => length + argument.length,
        ),
      ),
    );
  }
}
