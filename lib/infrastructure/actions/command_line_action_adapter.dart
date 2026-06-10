import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_preflight_metadata.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:result_dart/result_dart.dart';

class CommandLineActionAdapter implements AgentActionAdapter {
  CommandLineActionAdapter({
    ActionCommandNormalizer commandNormalizer = const ActionCommandNormalizer(),
    ActionPathValidator? pathValidator,
    DateTime Function()? now,
  }) : _commandNormalizer = commandNormalizer,
       _pathValidator = pathValidator ?? ActionPathValidator(),
       _now = now ?? DateTime.now;

  final ActionCommandNormalizer _commandNormalizer;
  final ActionPathValidator _pathValidator;
  final DateTime Function() _now;

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    final config = definition.config;
    if (config is! CommandLineActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Command line action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.commandLine.name,
            'phase': AgentActionProcessConstants.definitionValidationPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de linha de comando e invalida.',
          },
        ),
      );
    }

    final invocationResult = _commandNormalizer.normalizeCommandLine(
      actionId: definition.id,
      command: config.command,
    );
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }
    final invocation = invocationResult.getOrThrow();

    final workingDirectoryValidation = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
    );
    if (workingDirectoryValidation.isError()) {
      return Failure(workingDirectoryValidation.exceptionOrNull()!);
    }
    final hasWorkingDirectory = config.workingDirectory != null;

    return Success(
      AgentActionPreflight(
        actionType: type,
        canRun: definition.canRun,
        safeMessage: definition.canRun
            ? 'Command line action is ready to run.'
            : 'Command line action is valid but not active.',
        redactedDiagnostics: {
          'command_length': invocation.normalizedCommandLength,
          'has_working_directory': hasWorkingDirectory,
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final config = definition.config;
    if (config is! CommandLineActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Command line action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.commandLine.name,
            'phase': AgentActionProcessConstants.executionPreflightPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de linha de comando e invalida.',
          },
        ),
      );
    }

    final invocationResult = _commandNormalizer.normalizeCommandLine(
      actionId: definition.id,
      command: config.command,
      phase: 'execution_preflight',
    );
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }
    final invocation = invocationResult.getOrThrow();

    final workingDirectoryValidation = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
      phase: 'execution_preflight',
    );
    if (workingDirectoryValidation.isError()) {
      return Failure(workingDirectoryValidation.exceptionOrNull()!);
    }

    final redactedDiagnostics = <String, Object?>{
      'command_length': invocation.normalizedCommandLength,
    };

    final pathSnapshotResult = _pathValidator.guardPathSnapshot(
      actionId: definition.id,
      field: 'workingDirectory',
      savedReference: config.workingDirectory,
      currentPath: workingDirectoryValidation.getOrThrow().path,
      diagnostics: redactedDiagnostics,
    );
    if (pathSnapshotResult.isError()) {
      return Failure(pathSnapshotResult.exceptionOrNull()!);
    }

    final contextValidation = await _pathValidator.validateContextFile(
      actionId: definition.id,
      contextPath: request.contextPath,
      policy: definition.policies.context,
      pathPolicy: definition.policies.path,
    );
    if (contextValidation.isError()) {
      return Failure(contextValidation.exceptionOrNull()!);
    }

    return Success(
      AgentActionPreparedExecution(
        actionType: type,
        redactedCommandPreview: invocation.redactedPreview,
        workingDirectory:
            workingDirectoryValidation.getOrThrow().path?.canonicalPath ?? config.workingDirectory?.displayPath,
        contextHash: contextValidation.getOrThrow().path?.contentHash,
        redactedDiagnostics: {
          ...redactedDiagnostics,
          'context_path_extension': extensionOf(request.contextPath),
          'uses_context_path': request.contextPath != null,
          if (workingDirectoryValidation.getOrThrow().path != null)
            'working_directory': ActionPathPreflightMetadata.forValidatedPath(
              workingDirectoryValidation.getOrThrow().path!,
            ),
          if (contextValidation.getOrThrow().path != null)
            'context_path': ActionPathPreflightMetadata.forValidatedPath(
              contextValidation.getOrThrow().path!,
            ),
        },
      ),
    );
  }

  Future<Result<AgentActionCommandInvocation>> resolveInvocationCommand(
    AgentActionDefinition definition, {
    String phase = 'execution_preflight',
  }) async {
    final config = definition.config;
    if (config is! CommandLineActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Command line action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.commandLine.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de linha de comando e invalida.',
          },
        ),
      );
    }

    return _commandNormalizer.normalizeCommandLine(
      actionId: definition.id,
      command: config.command,
      phase: phase,
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    final config = definition.config;
    if (config is! CommandLineActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Command line action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.commandLine.name,
            'phase': AgentActionProcessConstants.definitionValidationPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de linha de comando e invalida.',
          },
        ),
      );
    }

    final workingDirectoryValidation = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
    );
    if (workingDirectoryValidation.isError()) {
      return Failure(workingDirectoryValidation.exceptionOrNull()!);
    }

    final normalizedWorkingDirectory = _normalizedWorkingDirectory(
      originalPath: config.workingDirectory,
      validation: workingDirectoryValidation.getOrThrow(),
    );
    return Success(
      definition.copyWith(
        config: CommandLineActionConfig(
          command: config.command,
          workingDirectory: normalizedWorkingDirectory,
        ),
      ),
    );
  }

  AgentActionPathReference? _normalizedWorkingDirectory({
    required AgentActionPathReference? originalPath,
    required AgentActionPathValidation validation,
  }) {
    final validatedPath = validation.path;
    if (validatedPath == null) {
      return originalPath;
    }

    return AgentActionPathReference(
      originalPath: validatedPath.originalPath,
      canonicalPath: validatedPath.canonicalPath,
      existsAtValidation: true,
      validatedAt: _now().toUtc(),
      validationHash: validatedPath.contentHash ?? originalPath?.validationHash,
      pathChangePolicy: originalPath?.pathChangePolicy,
    );
  }
}
