import 'package:plug_agente/application/actions/agent_action_secret_placeholder_scanner.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_secret_store.dart';
import 'package:result_dart/result_dart.dart';

/// Resolves `${secret:name}` placeholders using [IAgentActionSecretStore] at execution time.
class AgentActionSecretPlaceholderResolver {
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
        return Success(
          definition.copyWith(
            config: CommandLineActionConfig(
              command: commandResult.getOrThrow(),
              workingDirectory: workingDirectory,
            ),
          ),
        );
      case ExecutableActionConfig(
        :final executablePath,
        :final arguments,
        :final workingDirectory,
      ):
        return _resolveDefinitionWithStringList(
          definition: definition,
          arguments: arguments,
          buildConfig: (resolvedArguments) => ExecutableActionConfig(
            executablePath: executablePath,
            arguments: resolvedArguments,
            workingDirectory: workingDirectory,
          ),
        );
      case ScriptActionConfig(
        :final scriptPath,
        :final interpreterPath,
        :final arguments,
        :final workingDirectory,
      ):
        return _resolveDefinitionWithStringList(
          definition: definition,
          arguments: arguments,
          buildConfig: (resolvedArguments) => ScriptActionConfig(
            scriptPath: scriptPath,
            interpreterPath: interpreterPath,
            arguments: resolvedArguments,
            workingDirectory: workingDirectory,
          ),
        );
      case JarActionConfig(
        :final jarPath,
        :final javaExecutablePath,
        :final arguments,
        :final workingDirectory,
      ):
        return _resolveDefinitionWithStringList(
          definition: definition,
          arguments: arguments,
          buildConfig: (resolvedArguments) => JarActionConfig(
            jarPath: jarPath,
            javaExecutablePath: javaExecutablePath,
            arguments: resolvedArguments,
            workingDirectory: workingDirectory,
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
        final labelResult = await resolveText(
          text: connectionLabel,
          actionId: definition.id,
        );
        if (labelResult.isError()) {
          return Failure(labelResult.exceptionOrNull()!);
        }
        final config = definition.config as DeveloperActionConfig;
        return Success(
          definition.copyWith(
            config: DeveloperActionConfig.data7Executor(
              executorPath: config.executorPath,
              projectPath: config.projectPath,
              data7ConfigPath: config.data7ConfigPath,
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
          attachmentPaths: attachmentPaths,
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
          progId: progId,
          memberName: memberName,
          arguments: resolvedArguments,
        ),
      ),
    );
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
