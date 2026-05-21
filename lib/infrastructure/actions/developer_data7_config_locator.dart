import 'package:plug_agente/core/constants/agent_action_developer_data7_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_path_validator.dart';
import 'package:result_dart/result_dart.dart';

class DeveloperData7LocatedConfigPath {
  const DeveloperData7LocatedConfigPath({
    required this.path,
    required this.usedDefaultLocation,
  });

  final AgentActionValidatedPath path;
  final bool usedDefaultLocation;
}

class DeveloperData7ConfigLocator {
  DeveloperData7ConfigLocator({
    ActionPathValidator? pathValidator,
    List<String> defaultPaths = const <String>[
      r'C:\Data7\bin\Data7.Config',
      r'C:\Data7\Data7.Config',
    ],
  }) : _pathValidator = pathValidator ?? ActionPathValidator(),
       _defaultPaths = List<String>.unmodifiable(defaultPaths);

  final ActionPathValidator _pathValidator;
  final List<String> _defaultPaths;

  Future<Result<DeveloperData7LocatedConfigPath>> locate({
    required String actionId,
    required AgentActionPathReference configuredPath,
    required AgentActionPathPolicy pathPolicy,
    required String phase,
  }) async {
    final configuredDisplayPath = configuredPath.displayPath.trim();
    if (configuredDisplayPath.isNotEmpty) {
      return _validateCandidate(
        actionId: actionId,
        candidatePath: configuredDisplayPath,
        pathPolicy: pathPolicy,
        phase: phase,
        usedDefaultLocation: false,
      );
    }

    for (final candidatePath in _defaultPaths) {
      final result = await _validateCandidate(
        actionId: actionId,
        candidatePath: candidatePath,
        pathPolicy: pathPolicy,
        phase: phase,
        usedDefaultLocation: true,
      );
      if (result.isSuccess()) {
        return result;
      }

      final failure = result.exceptionOrNull();
      if (failure is ActionValidationFailure &&
          failure.context['reason'] != AgentActionDeveloperData7Constants.developerData7ConfigNotFoundReason) {
        return Failure(failure);
      }
    }

    return Failure(
      ActionValidationFailure.withContext(
        message: 'Developer Data7 configuration file was not found in the configured or default locations.',
        code: 'DEVELOPER_DATA7_CONFIG_NOT_FOUND',
        context: {
          'action_id': actionId,
          'field': 'data7ConfigPath',
          'phase': phase,
          'searched_paths': _defaultPaths.toList(growable: false),
          'reason': AgentActionDeveloperData7Constants.developerData7ConfigNotFoundReason,
          'user_message': 'Nao foi possivel localizar o arquivo Data7.Config. Informe o caminho manualmente.',
        },
      ),
    );
  }

  Future<Result<DeveloperData7LocatedConfigPath>> _validateCandidate({
    required String actionId,
    required String candidatePath,
    required AgentActionPathPolicy pathPolicy,
    required String phase,
    required bool usedDefaultLocation,
  }) async {
    if (!_isData7ConfigFileName(candidatePath)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Developer Data7 configuration path must point to Data7.Config.',
          code: 'DEVELOPER_DATA7_CONFIG_FILE_NAME_INVALID',
          context: {
            'action_id': actionId,
            'field': 'data7ConfigPath',
            'phase': phase,
            'path': candidatePath,
            'reason': AgentActionDeveloperData7Constants.developerData7ConfigFileNameInvalidReason,
            'user_message': 'Selecione o arquivo Data7.Config correto para esta acao.',
          },
        ),
      );
    }

    final validationResult = await _pathValidator.validateRequiredFile(
      actionId: actionId,
      field: 'data7ConfigPath',
      path: AgentActionPathReference(originalPath: candidatePath),
      allowedExtensions: const {'.config'},
      allowedDirectories: pathPolicy.allowedWorkingDirectories,
      phase: phase,
      invalidPathReason: AgentActionDeveloperData7Constants.developerData7ConfigInvalidPathReason,
      notFoundReason: AgentActionDeveloperData7Constants.developerData7ConfigNotFoundReason,
      extensionNotAllowedReason: AgentActionDeveloperData7Constants.developerData7ConfigExtensionNotAllowedReason,
      notAllowedReason: AgentActionDeveloperData7Constants.developerData7ConfigNotAllowedReason,
      invalidPathUserMessage: 'Informe um caminho valido para o arquivo Data7.Config.',
      notFoundUserMessage: 'Arquivo Data7.Config nao encontrado no caminho informado.',
      extensionNotAllowedUserMessage: 'Selecione o arquivo Data7.Config com extensao valida.',
      notAllowedUserMessage: 'O arquivo Data7.Config esta fora dos diretorios permitidos para esta acao.',
    );
    if (validationResult.isError()) {
      return Failure(validationResult.exceptionOrNull()!);
    }

    return Success(
      DeveloperData7LocatedConfigPath(
        path: validationResult.getOrThrow().path!,
        usedDefaultLocation: usedDefaultLocation,
      ),
    );
  }

  bool _isData7ConfigFileName(String path) {
    final normalized = path.replaceAll(r'\', '/');
    final lastSeparator = normalized.lastIndexOf('/');
    final fileName = lastSeparator >= 0 ? normalized.substring(lastSeparator + 1) : normalized;
    return fileName.toLowerCase() == 'data7.config';
  }
}
