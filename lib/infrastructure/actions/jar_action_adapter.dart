import 'package:plug_agente/core/constants/agent_action_jar_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/action_path_preflight_metadata.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

class JarActionAdapter implements AgentActionAdapter {
  JarActionAdapter({
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
  AgentActionType get type => AgentActionType.jar;

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
        safeMessage: definition.canRun ? 'Jar action is ready to run.' : 'Jar action is valid but not active.',
        redactedDiagnostics: {
          'argument_count': resolved.invocation.arguments.length,
          'has_working_directory': resolved.hasWorkingDirectory,
          'uses_default_java': resolved.usesDefaultJava,
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

    final jarSnapshotResult = _pathValidator.guardPathSnapshot(
      actionId: definition.id,
      field: 'jarPath',
      savedReference: config.jarPath,
      currentPath: resolved.jarPath,
      diagnostics: redactedDiagnostics,
    );
    if (jarSnapshotResult.isError()) {
      return Failure(jarSnapshotResult.exceptionOrNull()!);
    }

    if (config.javaExecutablePath != null && resolved.javaExecutablePath != null) {
      final javaSnapshotResult = _pathValidator.guardPathSnapshot(
        actionId: definition.id,
        field: 'javaExecutablePath',
        savedReference: config.javaExecutablePath,
        currentPath: resolved.javaExecutablePath,
        diagnostics: redactedDiagnostics,
      );
      if (javaSnapshotResult.isError()) {
        return Failure(javaSnapshotResult.exceptionOrNull()!);
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
          'uses_default_java': resolved.usesDefaultJava,
          'jar_path': ActionPathPreflightMetadata.forValidatedPath(resolved.jarPath),
          if (resolved.javaExecutablePath != null)
            'java_executable_path': ActionPathPreflightMetadata.forValidatedPath(resolved.javaExecutablePath!),
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
    if (config is! JarActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Jar action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.jar.name,
            'phase': AgentActionProcessConstants.definitionValidationPhase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao .jar e invalida.',
          },
        ),
      );
    }

    final jarValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'jarPath',
      path: config.jarPath,
      allowedExtensions: AgentActionJarConstants.allowedJarExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
    );
    if (jarValidation.isError()) {
      return Failure(jarValidation.exceptionOrNull()!);
    }

    Result<AgentActionPathValidation>? javaValidation;
    if (config.javaExecutablePath != null) {
      javaValidation = await _pathValidator.validateRequiredFile(
        actionId: definition.id,
        field: 'javaExecutablePath',
        path: config.javaExecutablePath!,
        allowedExtensions: AgentActionJarConstants.allowedJavaExecutableExtensions,
        allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      );
      if (javaValidation.isError()) {
        return Failure(javaValidation.exceptionOrNull()!);
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
        config: JarActionConfig(
          jarPath: _normalizedPathReference(
            originalPath: config.jarPath,
            validation: jarValidation.getOrThrow(),
          ),
          javaExecutablePath: config.javaExecutablePath == null || javaValidation == null
              ? null
              : _normalizedPathReference(
                  originalPath: config.javaExecutablePath!,
                  validation: javaValidation.getOrThrow(),
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

  Future<Result<_ResolvedJarInvocation>> _resolveInvocation({
    required AgentActionDefinition definition,
    String phase = 'definition_validation',
  }) async {
    final config = definition.config;
    if (config is! JarActionConfig) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Jar action config is invalid.',
          context: {
            'action_id': definition.id,
            'action_type': definition.type.name,
            'expected_type': AgentActionType.jar.name,
            'phase': phase,
            'reason': AgentActionProcessConstants.invalidActionConfigReason,
            'user_message': 'A configuracao da acao .jar e invalida.',
          },
        ),
      );
    }

    final jarValidation = await _pathValidator.validateRequiredFile(
      actionId: definition.id,
      field: 'jarPath',
      path: config.jarPath,
      allowedExtensions: AgentActionJarConstants.allowedJarExtensions,
      allowedDirectories: definition.policies.path.allowedWorkingDirectories,
      phase: phase,
      invalidPathUserMessage: 'Informe um arquivo .jar valido para esta acao.',
      notFoundUserMessage: 'Arquivo .jar nao encontrado. Verifique o caminho informado.',
      extensionNotAllowedUserMessage: 'Selecione um arquivo .jar permitido para esta acao.',
      notAllowedUserMessage: 'O arquivo .jar esta fora dos diretorios permitidos para esta acao.',
    );
    if (jarValidation.isError()) {
      return Failure(jarValidation.exceptionOrNull()!);
    }
    final jarPath = jarValidation.getOrThrow().path!;

    final usesDefaultJava = config.javaExecutablePath == null;
    AgentActionValidatedPath? javaExecutablePath;
    String javaInvocationPath;
    if (config.javaExecutablePath != null) {
      final javaValidation = await _pathValidator.validateRequiredFile(
        actionId: definition.id,
        field: 'javaExecutablePath',
        path: config.javaExecutablePath!,
        allowedExtensions: AgentActionJarConstants.allowedJavaExecutableExtensions,
        allowedDirectories: definition.policies.path.allowedWorkingDirectories,
        phase: phase,
        requireLaunchAccess: WindowsExecutableLaunchAccessChecker.shouldValidateLaunchAccessForPath(
          phase: phase,
          path: config.javaExecutablePath!.displayPath,
        ),
        invalidPathUserMessage: 'Informe um caminho valido para o java.exe desta acao.',
        notFoundUserMessage: 'Java nao encontrado. Verifique o caminho informado.',
        extensionNotAllowedUserMessage: 'Selecione um java.exe permitido para esta acao.',
        notAllowedUserMessage: 'O java.exe esta fora dos diretorios permitidos para esta acao.',
      );
      if (javaValidation.isError()) {
        return Failure(javaValidation.exceptionOrNull()!);
      }
      javaExecutablePath = javaValidation.getOrThrow().path;
      javaInvocationPath = javaExecutablePath!.canonicalPath;
    } else {
      javaInvocationPath = AgentActionJarConstants.defaultJavaExecutableName;
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

    final invocationResult = _commandNormalizer.normalizeJar(
      actionId: definition.id,
      jarCanonicalPath: jarPath.canonicalPath,
      javaExecutablePath: javaInvocationPath,
      arguments: config.arguments,
      phase: phase,
    );
    if (invocationResult.isError()) {
      return Failure(invocationResult.exceptionOrNull()!);
    }

    return Success(
      _ResolvedJarInvocation(
        config: config,
        jarPath: jarPath,
        javaExecutablePath: javaExecutablePath,
        usesDefaultJava: usesDefaultJava,
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

class _ResolvedJarInvocation {
  const _ResolvedJarInvocation({
    required this.config,
    required this.jarPath,
    required this.javaExecutablePath,
    required this.usesDefaultJava,
    required this.workingDirectoryValidation,
    required this.invocation,
    required this.hasWorkingDirectory,
  });

  final JarActionConfig config;
  final AgentActionValidatedPath jarPath;
  final AgentActionValidatedPath? javaExecutablePath;
  final bool usesDefaultJava;
  final AgentActionPathValidation workingDirectoryValidation;
  final AgentActionCommandInvocation invocation;
  final bool hasWorkingDirectory;
}
