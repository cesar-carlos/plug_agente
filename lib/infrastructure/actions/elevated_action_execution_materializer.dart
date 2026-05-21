import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';
import 'package:plug_agente/infrastructure/actions/developer_data7_definition_resolver.dart';
import 'package:plug_agente/infrastructure/actions/elevated_protected_request.dart';
import 'package:result_dart/result_dart.dart';

/// Writes a short-lived launch plan for the elevated helper (resolved command, no secret placeholders).
class ElevatedActionExecutionMaterializer {

  ElevatedActionExecutionMaterializer({
    required GlobalStorageContext storageContext,
    DeveloperData7DefinitionResolver? developerResolver,
    ActionCommandNormalizer commandNormalizer = const ActionCommandNormalizer(),
  }) : _storageContext = storageContext,
       _developerResolver = developerResolver ?? DeveloperData7DefinitionResolver(),
       _commandNormalizer = commandNormalizer;
  static final RegExp _secretPlaceholderPattern = RegExp(
    r'\$\{secret:([^}]+)\}',
    caseSensitive: false,
  );

  final GlobalStorageContext _storageContext;
  final DeveloperData7DefinitionResolver _developerResolver;
  final ActionCommandNormalizer _commandNormalizer;

  Future<Result<void>> writeMaterializedLaunchPlan({
    required ElevatedProtectedRequest protectedRequest,
    required AgentActionDefinition definition,
  }) async {
    final launchResult = await _buildLaunch(definition);
    if (launchResult.isError()) {
      return Failure(launchResult.exceptionOrNull()!);
    }

    final materializedPath = AgentActionElevatedConstants.materializedFilePath(
      _storageContext.appDirectoryPath,
      protectedRequest.executionId,
    );
    final payload = <String, Object?>{
      'version': AgentActionElevatedConstants.materializedSchemaVersion,
      'executionId': protectedRequest.executionId,
      'nonce': protectedRequest.nonce,
      'expiresAt': protectedRequest.expiresAt.toUtc().toIso8601String(),
      'actionType': definition.type.name,
      'launch': launchResult.getOrThrow(),
    };

    try {
      final directory = Directory(
        AgentActionElevatedConstants.materializedDirectoryPath(_storageContext.appDirectoryPath),
      );
      await directory.create(recursive: true);
      final tempPath = '$materializedPath.tmp';
      await File(tempPath).writeAsString(jsonEncode(payload), flush: true);
      await File(tempPath).rename(materializedPath);
      return const Success(unit);
    } on IOException catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Unable to write elevated materialized launch plan.',
          code: AgentActionFailureCode.elevatedRequestProtectionFailed,
          cause: error,
          context: {
            'execution_id': protectedRequest.executionId,
            'reason': AgentActionGateConstants.elevatedRequestProtectionFailedReason,
            'user_message': 'Nao foi possivel preparar o plano de execucao elevada.',
          },
        ),
      );
    }
  }

  Future<Result<Map<String, Object?>>> _buildLaunch(AgentActionDefinition definition) async {
    switch (definition.config) {
      case CommandLineActionConfig(:final command, :final workingDirectory):
        if (_containsUnresolvedPlaceholder(command)) {
          return Failure(_unresolvedSecretFailure(definition.id));
        }
        final invocationResult = _commandNormalizer.normalizeCommandLine(
          actionId: definition.id,
          command: command,
          phase: 'execution_preflight',
        );
        if (invocationResult.isError()) {
          return Failure(invocationResult.exceptionOrNull()!);
        }
        final invocation = invocationResult.getOrThrow();
        return Success(<String, Object?>{
          'executable': invocation.executable,
          'arguments': invocation.arguments,
          'workingDirectory': _pathFromReference(workingDirectory),
          'commandPreview': AgentActionProcessInvocationDiagnostics.logSafeCommandPreview(
            invocation: invocation,
            capturePolicy: definition.policies.capture,
          ),
        });
      case DeveloperActionConfig(:final connectionLabel):
        if (_containsUnresolvedPlaceholder(connectionLabel)) {
          return Failure(_unresolvedSecretFailure(definition.id));
        }
        final preparedResult = await _developerResolver.prepareExecution(
          definition: definition,
          request: AgentActionExecutionRequest(
            actionId: definition.id,
            source: AgentActionRequestSource.localUi,
          ),
        );
        if (preparedResult.isError()) {
          return Failure(preparedResult.exceptionOrNull()!);
        }
        final command = preparedResult.getOrThrow().command;
        return Success(<String, Object?>{
          'executable': command.executable,
          'arguments': command.arguments,
          'workingDirectory': command.workingDirectory,
          'commandPreview': command.redactedPreview,
        });
      default:
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Action type is not supported by the elevated materializer.',
            code: AgentActionFailureCode.unsupportedForElevatedRunner,
            context: {
              'action_id': definition.id,
              'action_type': definition.type.name,
              'reason': AgentActionGateConstants.unsupportedForElevatedRunnerReason,
            },
          ),
        );
    }
  }

  bool _containsUnresolvedPlaceholder(String text) {
    return _secretPlaceholderPattern.hasMatch(text);
  }

  String? _pathFromReference(AgentActionPathReference? reference) {
    if (reference == null) {
      return null;
    }
    final path = reference.canonicalPath?.trim().isNotEmpty ?? false
        ? reference.canonicalPath!.trim()
        : reference.originalPath.trim();
    if (path.isEmpty) {
      return null;
    }
    return path;
  }

  ActionRuntimeFailure _unresolvedSecretFailure(String actionId) {
    return ActionRuntimeFailure.withContext(
      message: 'Elevated launch plan still contains unresolved secret placeholders.',
      code: AgentActionFailureCode.secretUnavailable,
      context: {
        'action_id': actionId,
        'reason': AgentActionGateConstants.secretUnavailableReason,
        'user_message': 'Resolva os segredos da acao antes de executar com privilegio elevado.',
      },
    );
  }
}
