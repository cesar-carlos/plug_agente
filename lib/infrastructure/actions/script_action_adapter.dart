import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_script_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_preflight_metadata.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

class ScriptActionAdapter implements AgentActionAdapter {
  ScriptActionAdapter({
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
  AgentActionType get type => AgentActionType.script;

  @override
  Future<Result<AgentActionPreflight>> validateDefinition(
    AgentActionDefinition definition,
  ) async {
    final resolvedResult = await _resolveInvocation(
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
        safeMessage: definition.canRun ? 'Script action is ready to run.' : 'Script action is valid but not active.',
        redactedDiagnostics: {
          'argument_count': resolved.invocation.arguments.length,
          'has_working_directory': resolved.hasWorkingDirectory,
          'script_extension': resolved.scriptExtension,
          'uses_default_interpreter': resolved.usesDefaultInterpreter,
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionPreparedExecution>> prepareExecution({
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    final resolvedResult = await _resolveInvocation(
      definition: definition,
      phase: 'execution_preflight',
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }
    final resolved = resolvedResult.getOrThrow();
    final config = resolved.config;

    final redactedDiagnostics = <String, Object?>{};

    final scriptSnapshotResult = _pathValidator.guardPathSnapshot(
      actionId: definition.id,
      field: 'scriptPath',
      savedReference: config.scriptPath,
      currentPath: resolved.scriptPath,
      diagnostics: redactedDiagnostics,
    );
    if (scriptSnapshotResult.isError()) {
      return Failure(scriptSnapshotResult.exceptionOrNull()!);
    }

    if (config.interpreterPath != null && resolved.interpreterPath != null) {
      final interpreterSnapshotResult = _pathValidator.guardPathSnapshot(
        actionId: definition.id,
        field: 'interpreterPath',
        savedReference: config.interpreterPath,
        currentPath: resolved.interpreterPath,
        diagnostics: redactedDiagnostics,
      );
      if (interpreterSnapshotResult.isError()) {
        return Failure(interpreterSnapshotResult.exceptionOrNull()!);
      }
    }

    final workingDirectorySnapshotResult = _pathValidator.guardPathSnapshot(
      actionId: definition.id,
      field: 'workingDirectory',
      savedReference: config.workingDirectory,
      currentPath: resolved.workingDirectoryValidation.path,
      diagnostics: redactedDiagnostics,
    );
    if (workingDirectorySnapshotResult.isError()) {
      return Failure(workingDirectorySnapshotResult.exceptionOrNull()!);
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
        redactedCommandPreview: resolved.invocation.redactedPreview,
        workingDirectory:
            resolved.workingDirectoryValidation.path?.canonicalPath ?? config.workingDirectory?.displayPath,
        contextHash: contextValidation.getOrThrow().path?.contentHash,
        redactedDiagnostics: {
          ...redactedDiagnostics,
          'argument_count': resolved.invocation.arguments.length,
          'context_path_extension': extensionOf(request.contextPath),
          'uses_context_path': request.contextPath != null,
          'script_extension': resolved.scriptExtension,
          'uses_default_interpreter': resolved.usesDefaultInterpreter,
          'script_path': ActionPathPreflightMetadata.forValidatedPath(resolved.scriptPath),
          if (resolved.interpreterPath != null)
            'interpreter_path': ActionPathPreflightMetadata.forValidatedPath(resolved.interpreterPath!),
          if (resolved.workingDirectoryValidation.path != null)
            'working_directory': ActionPathPreflightMetadata.forValidatedPath(
              resolved.workingDirectoryValidation.path!,
            ),
        },
      ),
    );
  }

  Future<Result<AgentActionCommandInvocation>> resolveInvocationCommand(
    AgentActionDefinition definition, {
    String phase = 'execution_preflight',
  }) async {
    final resolvedResult = await _resolveInvocation(
      definition: definition,
      phase: phase,
    );
    if (resolvedResult.isError()) {
      return Failure(resolvedResult.exceptionOrNull()!);
    }

    return Success(resolvedResult.getOrThrow().invocation);
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    final config = definition.config;
    if (config is! ScriptActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.script.name,
            'phase': AgentActionProcessConstants.definitionValidationPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de script e invalida.',
          },
        ),
      );
    }

    final scriptValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'scriptPath',
      path: config.scriptPath,
      allowedExtensions: AgentActionScriptConstants.allowedScriptExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
    );
    if (scriptValidation.isError()) {
      return Failure(scriptValidation.exceptionOrNull()!);
    }

    Result<AgentActionPathValidation>? interpreterValidation;
    if (config.interpreterPath != null) {
      interpreterValidation = await _pathValidator.validateRequiredFile(
        actionId: definition.id,
        field: 'interpreterPath',
        path: config.interpreterPath!,
        allowedExtensions: AgentActionScriptConstants.allowedInterpreterExtensions,
        allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      );
      if (interpreterValidation.isError()) {
        return Failure(interpreterValidation.exceptionOrNull()!);
      }
    }

    final workingDirectoryValidation = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
    );
    if (workingDirectoryValidation.isError()) {
      return Failure(workingDirectoryValidation.exceptionOrNull()!);
    }

    return Success(
      definition.copyWith(
        config: ScriptActionConfig(
          scriptPath: _normalizedPathReference(
            originalPath: config.scriptPath,
            validation: scriptValidation.getOrThrow(),
          ),
          interpreterPath: config.interpreterPath == null || interpreterValidation == null
              ? null
              : _normalizedPathReference(
                  originalPath: config.interpreterPath!,
                  validation: interpreterValidation.getOrThrow(),
                ),
          arguments: config.arguments,
          workingDirectory: _normalizedWorkingDirectory(
            originalPath: config.workingDirectory,
            validation: workingDirectoryValidation.getOrThrow(),
          ),
        ),
      ),
    );
  }

  Future<Result<_ResolvedScriptInvocation>> _resolveInvocation({
    required AgentActionDefinition definition,
    String phase = 'definition_validation',
  }) async {
    final config = definition.config;
    if (config is! ScriptActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.script.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao de script e invalida.',
          },
        ),
      );
    }

    final scriptValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'scriptPath',
      path: config.scriptPath,
      allowedExtensions: AgentActionScriptConstants.allowedScriptExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      phase: phase,
      invalidPathUserMessage: 'Informe um arquivo de script valido para esta acao.',
      notFoundUserMessage: 'Arquivo de script nao encontrado. Verifique o caminho informado.',
      extensionNotAllowedUserMessage: 'Selecione um script .ps1, .bat, .cmd ou .py permitido para esta acao.',
      notAllowedUserMessage: 'O script esta fora dos diretorios permitidos para esta acao.',
    );
    if (scriptValidation.isError()) {
      return Failure(scriptValidation.exceptionOrNull()!);
    }
    final scriptPath = scriptValidation.getOrThrow().path!;
    final scriptExtension = extensionOf(scriptPath.originalPath);
    if (scriptExtension == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Script extension is required.',
          context: {
            'action_id': definition.id,
            'field': 'scriptPath',
            'phase': phase,
            'reason': AgentActionScriptConstants.unsupportedScriptExtensionReason,
            'user_message': 'Selecione um script .ps1, .bat, .cmd ou .py permitido para esta acao.',
          },
        ),
      );
    }

    final usesDefaultInterpreter = config.interpreterPath == null;
    AgentActionValidatedPath? interpreterPath;
    String interpreterInvocationPath;
    if (config.interpreterPath != null) {
      final interpreterValidation = await _pathValidator.validateRequiredFile(
        actionId: definition.id,
        field: 'interpreterPath',
        path: config.interpreterPath!,
        allowedExtensions: AgentActionScriptConstants.allowedInterpreterExtensions,
        allowedDirectories: definition.policies.path.allowedWorkingDirectories,
        phase: phase,
        requireLaunchAccess: WindowsExecutableLaunchAccessChecker.shouldValidateLaunchAccess(
          phase: phase,
          extension: extensionOf(config.interpreterPath!.displayPath),
        ),
        invalidPathUserMessage: 'Informe um interpretador .exe valido para esta acao.',
        notFoundUserMessage: 'Interpretador nao encontrado. Verifique o caminho informado.',
        extensionNotAllowedUserMessage: 'Selecione um interpretador .exe permitido para esta acao.',
        notAllowedUserMessage: 'O interpretador esta fora dos diretorios permitidos para esta acao.',
      );
      if (interpreterValidation.isError()) {
        return Failure(interpreterValidation.exceptionOrNull()!);
      }
      interpreterPath = interpreterValidation.getOrThrow().path;
      interpreterInvocationPath = interpreterPath!.canonicalPath;
    } else {
      final defaultInterpreter = AgentActionScriptConstants.defaultInterpreterExecutableNames[scriptExtension];
      if (defaultInterpreter == null) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Script extension does not have a default interpreter.',
            context: {
              'action_id': definition.id,
              'field': 'scriptPath',
              'phase': phase,
              'extension': scriptExtension,
              'reason': AgentActionScriptConstants.unsupportedScriptExtensionReason,
              'user_message': 'Informe um interpretador .exe ou use um script com extensao suportada.',
            },
          ),
        );
      }
      interpreterInvocationPath = defaultInterpreter;
    }

    final workingDirectoryValidation = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
      phase: phase,
    );
    if (workingDirectoryValidation.isError()) {
      return Failure(workingDirectoryValidation.exceptionOrNull()!);
    }

    final invocationResult = _commandNormalizer.normalizeScript(
      actionId: definition.id,
      scriptCanonicalPath: scriptPath.canonicalPath,
      interpreterCanonicalPath: interpreterInvocationPath,
      arguments: config.arguments,
      phase: phase,
    );
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }

    return Success(
      _ResolvedScriptInvocation(
        config: config,
        scriptPath: scriptPath,
        interpreterPath: interpreterPath,
        scriptExtension: scriptExtension,
        usesDefaultInterpreter: usesDefaultInterpreter,
        workingDirectoryValidation: workingDirectoryValidation.getOrThrow(),
        invocation: invocationResult.getOrThrow(),
        hasWorkingDirectory: config.workingDirectory != null,
      ),
    );
  }

  AgentActionPathReference _normalizedPathReference({
    required AgentActionPathReference originalPath,
    required AgentActionPathValidation validation,
  }) {
    final validatedPath = validation.path!;
    return AgentActionPathReference(
      originalPath: validatedPath.originalPath,
      canonicalPath: validatedPath.canonicalPath,
      existsAtValidation: true,
      validatedAt: _now().toUtc(),
      validationHash: validatedPath.contentHash ?? originalPath.validationHash,
      pathChangePolicy: originalPath.pathChangePolicy,
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

class _ResolvedScriptInvocation {
  const _ResolvedScriptInvocation({
    required this.config,
    required this.scriptPath,
    required this.interpreterPath,
    required this.scriptExtension,
    required this.usesDefaultInterpreter,
    required this.workingDirectoryValidation,
    required this.invocation,
    required this.hasWorkingDirectory,
  });

  final ScriptActionConfig config;
  final AgentActionValidatedPath scriptPath;
  final AgentActionValidatedPath? interpreterPath;
  final String scriptExtension;
  final bool usesDefaultInterpreter;
  final AgentActionPathValidation workingDirectoryValidation;
  final AgentActionCommandInvocation invocation;
  final bool hasWorkingDirectory;
}
