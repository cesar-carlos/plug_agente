import 'package:plug_agente/core/constants/agent_action_executable_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_preflight_metadata.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

class ExecutableActionAdapter implements AgentActionAdapter {
  ExecutableActionAdapter({
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
  AgentActionType get type => AgentActionType.executable;

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
        safeMessage: definition.canRun
            ? 'Executable action is ready to run.'
            : 'Executable action is valid but not active.',
        redactedDiagnostics: {
          'argument_count': resolved.invocation.arguments.length,
          'has_working_directory': resolved.hasWorkingDirectory,
          'run_in_shell': resolved.invocation.runInShell,
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

    final pathSnapshotResult = _pathValidator.guardPathSnapshot(
      actionId: definition.id,
      field: 'executablePath',
      savedReference: config.executablePath,
      currentPath: resolved.executablePath,
      diagnostics: redactedDiagnostics,
    );
    if (pathSnapshotResult.isError()) {
      return Failure(pathSnapshotResult.exceptionOrNull()!);
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
        redactedDiagnostics: {
          ...redactedDiagnostics,
          'argument_count': resolved.invocation.arguments.length,
          'context_path_extension': _extensionOf(request.contextPath),
          'uses_context_path': request.contextPath != null,
          'run_in_shell': resolved.invocation.runInShell,
          'executable_path': ActionPathPreflightMetadata.forValidatedPath(resolved.executablePath),
          if (resolved.workingDirectoryValidation.path != null)
            'working_directory': ActionPathPreflightMetadata.forValidatedPath(
              resolved.workingDirectoryValidation.path!,
            ),
        },
      ),
    );
  }

  @override
  Future<Result<AgentActionDefinition>> normalizeDefinition(
    AgentActionDefinition definition,
  ) async {
    final config = definition.config;
    if (config is! ExecutableActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Executable action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.executable.name,
            'phase': AgentActionProcessConstants.definitionValidationPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao executavel e invalida.',
          },
        ),
      );
    }

    final executableValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'executablePath',
      path: config.executablePath,
      allowedExtensions: AgentActionExecutableConstants.allowedExecutableExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
    );
    if (executableValidation.isError()) {
      return Failure(executableValidation.exceptionOrNull()!);
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
        config: ExecutableActionConfig(
          executablePath: _normalizedPathReference(
            originalPath: config.executablePath,
            validation: executableValidation.getOrThrow(),
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

  Future<Result<_ResolvedExecutableInvocation>> _resolveInvocation({
    required AgentActionDefinition definition,
    String phase = 'definition_validation',
  }) async {
    final config = definition.config;
    if (config is! ExecutableActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Executable action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.executable.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao executavel e invalida.',
          },
        ),
      );
    }

    final executableValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'executablePath',
      path: config.executablePath,
      allowedExtensions: AgentActionExecutableConstants.allowedExecutableExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      phase: phase,
      requireLaunchAccess: WindowsExecutableLaunchAccessChecker.shouldValidateLaunchAccess(
        phase: phase,
        extension: _extensionOf(config.executablePath.displayPath),
      ),
      invalidPathUserMessage: 'Informe um executavel ou arquivo .bat valido para esta acao.',
      notFoundUserMessage: 'Arquivo executavel nao encontrado. Verifique o caminho informado.',
      extensionNotAllowedUserMessage: 'Selecione um arquivo .exe, .bat ou .cmd permitido para esta acao.',
      notAllowedUserMessage: 'O executavel esta fora dos diretorios permitidos para esta acao.',
    );
    if (executableValidation.isError()) {
      return Failure(executableValidation.exceptionOrNull()!);
    }
    final executablePath = executableValidation.getOrThrow().path!;

    final workingDirectoryValidation = await _pathValidator.validateWorkingDirectory(
      actionId: definition.id,
      path: config.workingDirectory,
      pathPolicy: definition.policies.path,
      phase: phase,
    );
    if (workingDirectoryValidation.isError()) {
      return Failure(workingDirectoryValidation.exceptionOrNull()!);
    }

    final invocationResult = _commandNormalizer.normalizeExecutable(
      actionId: definition.id,
      executableCanonicalPath: executablePath.canonicalPath,
      arguments: config.arguments,
      phase: phase,
    );
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }

    return Success(
      _ResolvedExecutableInvocation(
        config: config,
        executablePath: executablePath,
        workingDirectoryValidation: workingDirectoryValidation.getOrThrow(),
        invocation: invocationResult.getOrThrow(),
        hasWorkingDirectory: config.workingDirectory != null,
      ),
    );
  }

  String? _extensionOf(String? path) {
    if (path == null) {
      return null;
    }
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    final fileName = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return null;
    }
    return fileName.substring(dotIndex).toLowerCase();
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

class _ResolvedExecutableInvocation {
  const _ResolvedExecutableInvocation({
    required this.config,
    required this.executablePath,
    required this.workingDirectoryValidation,
    required this.invocation,
    required this.hasWorkingDirectory,
  });

  final ExecutableActionConfig config;
  final AgentActionValidatedPath executablePath;
  final AgentActionPathValidation workingDirectoryValidation;
  final AgentActionCommandInvocation invocation;
  final bool hasWorkingDirectory;
}
