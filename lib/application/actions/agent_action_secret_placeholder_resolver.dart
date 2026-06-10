import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/actions/i_agent_action_secret_placeholder_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:result_dart/result_dart.dart';

/// Resolves `${secret:name}` placeholders using [IAgentActionSecretStore] at execution time.
class AgentActionSecretPlaceholderResolver implements IAgentActionSecretPlaceholderResolver {
  const AgentActionSecretPlaceholderResolver({IAgentActionSecretStore? secretStore}) : _secretStore = secretStore;

  final IAgentActionSecretStore? _secretStore;

  Future<Result<void>> ensureResolvable(AgentActionDefinition definition) async {
    final referenced = AgentActionSecretPlaceholderScanner.collectFromDefinition(definition);
    if (referenced.isEmpty) {
      return const Success(unit);
    }

    final store = _secretStore;
    if (store == null || !store.isAvailable) {
      return Failure(
        _secretUnavailableFailure(
          actionId: definition.id,
          missingSecretNames: referenced,
          message: 'Action secret store is not available.',
          userMessage: 'Os segredos referenciados pela acao nao estao disponiveis neste agente.',
        ),
      );
    }

    final missing = <String>{};
    for (final name in referenced) {
      if (!await store.exists(name)) {
        missing.add(name);
      }
    }
    if (missing.isNotEmpty) {
      return Failure(
        _secretUnavailableFailure(
          actionId: definition.id,
          missingSecretNames: missing,
          message: 'One or more action secrets are missing.',
          userMessage: 'Configure os segredos ausentes antes de executar a acao.',
        ),
      );
    }

    return const Success(unit);
  }

  Future<Result<AgentActionDefinition>> resolveForExecution(
    AgentActionDefinition definition,
  ) async {
    final ensureResult = await ensureResolvable(definition);
    if (ensureResult.isError()) {
      return Failure(ensureResult.exceptionOrNull()!);
    }

    final referenced = AgentActionSecretPlaceholderScanner.collectFromDefinition(definition);
    if (referenced.isEmpty) {
      return Success(definition);
    }

    switch (definition.config) {
      case CommandLineActionConfig(:final command, :final workingDirectory):
        final commandResult = await resolveText(
          text: command,
          actionId: definition.id,
        );
        if (commandResult.isError()) {
          return Failure(commandResult.exceptionOrNull()!);
        }
        final workingDirectoryResult = await _resolveOptionalPathReference(
          path: workingDirectory,
          actionId: definition.id,
        );
        if (workingDirectoryResult.isError()) {
          return Failure(workingDirectoryResult.exceptionOrNull()!);
        }
        return Success(
          definition.copyWith(
            config: CommandLineActionConfig(
              command: commandResult.getOrThrow(),
              workingDirectory: workingDirectoryResult.getOrThrow().path,
            ),
          ),
        );
      case ExecutableActionConfig(
        :final executablePath,
        :final arguments,
        :final workingDirectory,
      ):
        final executablePathResult = await _resolvePathReference(
          path: executablePath,
          actionId: definition.id,
        );
        if (executablePathResult.isError()) {
          return Failure(executablePathResult.exceptionOrNull()!);
        }
        final workingDirectoryResult = await _resolveOptionalPathReference(
          path: workingDirectory,
          actionId: definition.id,
        );
        if (workingDirectoryResult.isError()) {
          return Failure(workingDirectoryResult.exceptionOrNull()!);
        }
        return _resolveDefinitionWithStringList(
          definition: definition,
          arguments: arguments,
          buildConfig: (resolvedArguments) => ExecutableActionConfig(
            executablePath: executablePathResult.getOrThrow(),
            arguments: resolvedArguments,
            workingDirectory: workingDirectoryResult.getOrThrow().path,
          ),
        );
      case ScriptActionConfig(
        :final scriptPath,
        :final interpreterPath,
        :final arguments,
        :final workingDirectory,
      ):
        final scriptPathResult = await _resolvePathReference(
          path: scriptPath,
          actionId: definition.id,
        );
        if (scriptPathResult.isError()) {
          return Failure(scriptPathResult.exceptionOrNull()!);
        }
        final interpreterPathResult = await _resolveOptionalPathReference(
          path: interpreterPath,
          actionId: definition.id,
        );
        if (interpreterPathResult.isError()) {
          return Failure(interpreterPathResult.exceptionOrNull()!);
        }
        final workingDirectoryResult = await _resolveOptionalPathReference(
          path: workingDirectory,
          actionId: definition.id,
        );
        if (workingDirectoryResult.isError()) {
          return Failure(workingDirectoryResult.exceptionOrNull()!);
        }
        return _resolveDefinitionWithStringList(
          definition: definition,
          arguments: arguments,
          buildConfig: (resolvedArguments) => ScriptActionConfig(
            scriptPath: scriptPathResult.getOrThrow(),
            interpreterPath: interpreterPathResult.getOrThrow().path,
            arguments: resolvedArguments,
            workingDirectory: workingDirectoryResult.getOrThrow().path,
          ),
        );
      case JarActionConfig(
        :final jarPath,
        :final javaExecutablePath,
        :final arguments,
        :final workingDirectory,
      ):
        final jarPathResult = await _resolvePathReference(
          path: jarPath,
          actionId: definition.id,
        );
        if (jarPathResult.isError()) {
          return Failure(jarPathResult.exceptionOrNull()!);
        }
        final javaExecutablePathResult = await _resolveOptionalPathReference(
          path: javaExecutablePath,
          actionId: definition.id,
        );
        if (javaExecutablePathResult.isError()) {
          return Failure(javaExecutablePathResult.exceptionOrNull()!);
        }
        final workingDirectoryResult = await _resolveOptionalPathReference(
          path: workingDirectory,
          actionId: definition.id,
        );
        if (workingDirectoryResult.isError()) {
          return Failure(workingDirectoryResult.exceptionOrNull()!);
        }
        return _resolveDefinitionWithStringList(
          definition: definition,
          arguments: arguments,
          buildConfig: (resolvedArguments) => JarActionConfig(
            jarPath: jarPathResult.getOrThrow(),
            javaExecutablePath: javaExecutablePathResult.getOrThrow().path,
            arguments: resolvedArguments,
            workingDirectory: workingDirectoryResult.getOrThrow().path,
          ),
        );
      case EmailActionConfig(
        :final smtpProfileId,
        :final from,
        :final to,
        :final cc,
        :final bcc,
        :final subjectTemplate,
        :final bodyTemplate,
        :final attachmentPaths,
      ):
        return _resolveEmailDefinition(
          definition: definition,
          smtpProfileId: smtpProfileId,
          from: from,
          to: to,
          cc: cc,
          bcc: bcc,
          subjectTemplate: subjectTemplate,
          bodyTemplate: bodyTemplate,
          attachmentPaths: attachmentPaths,
        );
      case ComObjectActionConfig(:final progId, :final memberName, :final arguments):
        return _resolveComObjectDefinition(
          definition: definition,
          progId: progId,
          memberName: memberName,
          arguments: arguments,
        );
      case DeveloperActionConfig(:final connectionLabel):
        final config = definition.config as DeveloperActionConfig;
        final executorPathResult = await _resolvePathReference(
          path: config.executorPath,
          actionId: definition.id,
        );
        if (executorPathResult.isError()) {
          return Failure(executorPathResult.exceptionOrNull()!);
        }
        final projectPathResult = await _resolvePathReference(
          path: config.projectPath,
          actionId: definition.id,
        );
        if (projectPathResult.isError()) {
          return Failure(projectPathResult.exceptionOrNull()!);
        }
        final data7ConfigPathResult = await _resolvePathReference(
          path: config.data7ConfigPath,
          actionId: definition.id,
        );
        if (data7ConfigPathResult.isError()) {
          return Failure(data7ConfigPathResult.exceptionOrNull()!);
        }
        final labelResult = await resolveText(
          text: connectionLabel,
          actionId: definition.id,
        );
        if (labelResult.isError()) {
          return Failure(labelResult.exceptionOrNull()!);
        }
        return Success(
          definition.copyWith(
            config: DeveloperActionConfig.data7Executor(
              executorPath: executorPathResult.getOrThrow(),
              projectPath: projectPathResult.getOrThrow(),
              data7ConfigPath: data7ConfigPathResult.getOrThrow(),
              connectionId: config.connectionId,
              connectionLabel: labelResult.getOrThrow(),
              connectionSnapshotHash: config.connectionSnapshotHash,
            ),
          ),
        );
    }
  }

  Future<Result<AgentActionDefinition>> _resolveDefinitionWithStringList({
    required AgentActionDefinition definition,
    required List<String> arguments,
    required AgentActionConfig Function(List<String> resolvedArguments) buildConfig,
  }) async {
    final resolvedArgumentsResult = await _resolveStringList(
      values: arguments,
      actionId: definition.id,
    );
    if (resolvedArgumentsResult.isError()) {
      return Failure(resolvedArgumentsResult.exceptionOrNull()!);
    }

    return Success(
      definition.copyWith(config: buildConfig(resolvedArgumentsResult.getOrThrow())),
    );
  }

  Future<Result<AgentActionDefinition>> _resolveEmailDefinition({
    required AgentActionDefinition definition,
    required String smtpProfileId,
    required String from,
    required List<String> to,
    required List<String> cc,
    required List<String> bcc,
    required String subjectTemplate,
    required String bodyTemplate,
    required List<AgentActionPathReference> attachmentPaths,
  }) async {
    final smtpProfileResult = await resolveText(
      text: smtpProfileId,
      actionId: definition.id,
    );
    if (smtpProfileResult.isError()) {
      return Failure(smtpProfileResult.exceptionOrNull()!);
    }
    final fromResult = await resolveText(text: from, actionId: definition.id);
    if (fromResult.isError()) {
      return Failure(fromResult.exceptionOrNull()!);
    }
    final subjectResult = await resolveText(text: subjectTemplate, actionId: definition.id);
    if (subjectResult.isError()) {
      return Failure(subjectResult.exceptionOrNull()!);
    }
    final bodyResult = await resolveText(text: bodyTemplate, actionId: definition.id);
    if (bodyResult.isError()) {
      return Failure(bodyResult.exceptionOrNull()!);
    }
    final toResult = await _resolveStringList(values: to, actionId: definition.id);
    if (toResult.isError()) {
      return Failure(toResult.exceptionOrNull()!);
    }
    final ccResult = await _resolveStringList(values: cc, actionId: definition.id);
    if (ccResult.isError()) {
      return Failure(ccResult.exceptionOrNull()!);
    }
    final bccResult = await _resolveStringList(values: bcc, actionId: definition.id);
    if (bccResult.isError()) {
      return Failure(bccResult.exceptionOrNull()!);
    }
    final attachmentPathsResult = await _resolvePathReferenceList(
      paths: attachmentPaths,
      actionId: definition.id,
    );
    if (attachmentPathsResult.isError()) {
      return Failure(attachmentPathsResult.exceptionOrNull()!);
    }

    return Success(
      definition.copyWith(
        config: EmailActionConfig(
          smtpProfileId: smtpProfileResult.getOrThrow(),
          from: fromResult.getOrThrow(),
          to: toResult.getOrThrow(),
          cc: ccResult.getOrThrow(),
          bcc: bccResult.getOrThrow(),
          subjectTemplate: subjectResult.getOrThrow(),
          bodyTemplate: bodyResult.getOrThrow(),
          attachmentPaths: attachmentPathsResult.getOrThrow(),
        ),
      ),
    );
  }

  Future<Result<AgentActionDefinition>> _resolveComObjectDefinition({
    required AgentActionDefinition definition,
    required String progId,
    required String memberName,
    required Map<String, Object?> arguments,
  }) async {
    final progIdResult = await resolveText(text: progId, actionId: definition.id);
    if (progIdResult.isError()) {
      return Failure(progIdResult.exceptionOrNull()!);
    }
    final memberNameResult = await resolveText(text: memberName, actionId: definition.id);
    if (memberNameResult.isError()) {
      return Failure(memberNameResult.exceptionOrNull()!);
    }

    final resolvedArguments = <String, Object?>{};
    for (final entry in arguments.entries) {
      final keyResult = await resolveText(text: entry.key, actionId: definition.id);
      if (keyResult.isError()) {
        return Failure(keyResult.exceptionOrNull()!);
      }
      final value = entry.value;
      if (value is String) {
        final valueResult = await resolveText(text: value, actionId: definition.id);
        if (valueResult.isError()) {
          return Failure(valueResult.exceptionOrNull()!);
        }
        resolvedArguments[keyResult.getOrThrow()] = valueResult.getOrThrow();
      } else {
        resolvedArguments[keyResult.getOrThrow()] = value;
      }
    }

    return Success(
      definition.copyWith(
        config: ComObjectActionConfig(
          progId: progIdResult.getOrThrow(),
          memberName: memberNameResult.getOrThrow(),
          arguments: resolvedArguments,
        ),
      ),
    );
  }

  Future<Result<_OptionalResolvedPath>> _resolveOptionalPathReference({
    required AgentActionPathReference? path,
    required String actionId,
  }) async {
    if (path == null) {
      return const Success(_OptionalResolvedPath(null));
    }

    final pathResult = await _resolvePathReference(path: path, actionId: actionId);
    if (pathResult.isError()) {
      return Failure(pathResult.exceptionOrNull()!);
    }

    return Success(_OptionalResolvedPath(pathResult.getOrThrow()));
  }

  Future<Result<AgentActionPathReference>> _resolvePathReference({
    required AgentActionPathReference path,
    required String actionId,
  }) async {
    final originalPathResult = await resolveText(
      text: path.originalPath,
      actionId: actionId,
    );
    if (originalPathResult.isError()) {
      return Failure(originalPathResult.exceptionOrNull()!);
    }

    String? resolvedCanonicalPath;
    final canonicalPath = path.canonicalPath;
    if (canonicalPath != null && canonicalPath.isNotEmpty) {
      final canonicalPathResult = await resolveText(
        text: canonicalPath,
        actionId: actionId,
      );
      if (canonicalPathResult.isError()) {
        return Failure(canonicalPathResult.exceptionOrNull()!);
      }
      resolvedCanonicalPath = canonicalPathResult.getOrThrow();
    }

    return Success(
      AgentActionPathReference(
        originalPath: originalPathResult.getOrThrow(),
        canonicalPath: resolvedCanonicalPath,
        existsAtValidation: path.existsAtValidation,
        validatedAt: path.validatedAt,
        validationHash: path.validationHash,
        pathChangePolicy: path.pathChangePolicy,
      ),
    );
  }

  Future<Result<List<AgentActionPathReference>>> _resolvePathReferenceList({
    required List<AgentActionPathReference> paths,
    required String actionId,
  }) async {
    if (paths.isEmpty) {
      return const Success(<AgentActionPathReference>[]);
    }

    final resolved = <AgentActionPathReference>[];
    for (final path in paths) {
      final pathResult = await _resolvePathReference(path: path, actionId: actionId);
      if (pathResult.isError()) {
        return Failure(pathResult.exceptionOrNull()!);
      }
      resolved.add(pathResult.getOrThrow());
    }

    return Success(List<AgentActionPathReference>.unmodifiable(resolved));
  }

  Future<Result<List<String>>> _resolveStringList({
    required List<String> values,
    required String actionId,
  }) async {
    if (values.isEmpty) {
      return const Success(<String>[]);
    }

    final resolved = <String>[];
    for (final value in values) {
      final valueResult = await resolveText(text: value, actionId: actionId);
      if (valueResult.isError()) {
        return Failure(valueResult.exceptionOrNull()!);
      }
      resolved.add(valueResult.getOrThrow());
    }

    return Success(List<String>.unmodifiable(resolved));
  }

  @override
  Future<Result<String>> resolveText({
    required String text,
    required String actionId,
    String phase = 'execution_preflight',
  }) async {
    if (text.isEmpty) {
      return Success(text);
    }

    final secretNames = AgentActionSecretPlaceholderScanner.collectFromText(text);
    if (secretNames.isEmpty) {
      return Success(text);
    }

    final store = _secretStore;
    if (store == null || !store.isAvailable) {
      return Failure(
        _secretUnavailableFailure(
          actionId: actionId,
          missingSecretNames: secretNames,
          phase: phase,
          message: 'Action secret store is not available.',
          userMessage: 'Os segredos referenciados pela acao nao estao disponiveis neste agente.',
        ),
      );
    }

    final valuesByName = <String, String>{};
    for (final name in secretNames) {
      final value = await store.readSecret(name);
      if (value == null || value.isEmpty) {
        return Failure(
          _secretUnavailableFailure(
            actionId: actionId,
            missingSecretNames: {name},
            phase: phase,
            message: 'Action secret "$name" is missing.',
            userMessage: 'Configure o segredo "$name" antes de executar a acao.',
          ),
        );
      }
      valuesByName[name] = value;
    }

    final resolved = text.replaceAllMapped(
      AgentActionSecretPlaceholderScanner.placeholderPattern,
      (match) {
        final name = match.group(1)?.trim();
        if (name == null || name.isEmpty) {
          return match.group(0) ?? '';
        }
        return valuesByName[name] ?? match.group(0) ?? '';
      },
    );
    return Success(resolved);
  }

  ActionValidationFailure _secretUnavailableFailure({
    required String actionId,
    required Set<String> missingSecretNames,
    required String message,
    required String userMessage,
    String phase = 'execution_preflight',
  }) {
    return ActionValidationFailure.withContext(
      message: message,
      code: AgentActionFailureCode.secretUnavailable,
      context: {
        'action_id': actionId,
        'phase': phase,
        'reason': AgentActionGateConstants.secretUnavailableReason,
        'missing_secrets': missingSecretNames.toList()..sort(),
        'user_message': userMessage,
      },
    );
  }
}

class _OptionalResolvedPath {
  const _OptionalResolvedPath(this.path);

  final AgentActionPathReference? path;
}
