import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_access_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_production_allowlist_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_helpers.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_types.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionPathExistenceValidator {
  AgentActionPathExistenceValidator({
    required AgentActionPathExists fileExists,
    required AgentActionPathExists directoryExists,
    required AgentActionPathCanonicalizer canonicalizeFile,
    required AgentActionPathCanonicalizer canonicalizeDirectory,
    required AgentActionFileLengthResolver fileLength,
    required AgentActionLaunchAccessValidator launchAccessValidator,
    required AgentActionPathProductionAllowlistValidator allowlistValidator,
  }) : _fileExists = fileExists,
       _directoryExists = directoryExists,
       _canonicalizeFile = canonicalizeFile,
       _canonicalizeDirectory = canonicalizeDirectory,
       _fileLength = fileLength,
       _launchAccessValidator = launchAccessValidator,
       _allowlistValidator = allowlistValidator;

  final AgentActionPathExists _fileExists;
  final AgentActionPathExists _directoryExists;
  final AgentActionPathCanonicalizer _canonicalizeFile;
  final AgentActionPathCanonicalizer _canonicalizeDirectory;
  final AgentActionFileLengthResolver _fileLength;
  final AgentActionLaunchAccessValidator _launchAccessValidator;
  final AgentActionPathProductionAllowlistValidator _allowlistValidator;

  Future<Result<AgentActionPathValidation>> validateWorkingDirectory({
    required String actionId,
    required AgentActionPathReference? path,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String phase = 'definition_validation',
  }) async {
    final productionAllowlistFailure = _allowlistValidator.validateProductionWorkingDirectoryAllowlist(
      actionId: actionId,
      pathPolicy: pathPolicy,
      phase: phase,
    );
    if (productionAllowlistFailure != null) {
      return Failure(productionAllowlistFailure);
    }

    final originalPath = path?.displayPath.trim();
    if (originalPath == null) {
      return const Success(AgentActionPathValidation.notProvided());
    }
    if (originalPath.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Working directory cannot be empty.',
          context: {
            'action_id': actionId,
            'field': 'workingDirectory',
            'phase': phase,
            'reason': AgentActionPathContextConstants.invalidPathReason,
            'user_message': 'Informe um diretorio de trabalho valido ou remova este campo.',
          },
        ),
      );
    }

    if (!await _directoryExists(originalPath)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Working directory was not found.',
          context: {
            'action_id': actionId,
            'field': 'workingDirectory',
            'phase': phase,
            'path': originalPath,
            'reason': AgentActionPathContextConstants.directoryNotFoundReason,
            'user_message': 'Diretorio de trabalho nao encontrado. Verifique se ele foi removido ou renomeado.',
          },
        ),
      );
    }

    final directoryAccessFailure = await AgentActionPathAccessValidator.validateDirectoryReadable(
      actionId: actionId,
      field: 'workingDirectory',
      path: originalPath,
      phase: phase,
    );
    if (directoryAccessFailure != null) {
      return Failure(directoryAccessFailure);
    }

    final canonicalPath = await _canonicalizeDirectory(originalPath);
    if (!await _allowlistValidator.isWithinAllowedDirectories(
      canonicalPath: canonicalPath,
      allowedDirectories: pathPolicy.allowedWorkingDirectories,
    )) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Working directory is outside the allowed directories for this action.',
          context: {
            'action_id': actionId,
            'field': 'workingDirectory',
            'phase': phase,
            'path': originalPath,
            'canonical_path': canonicalPath,
            'reason': AgentActionPathContextConstants.workingDirectoryNotAllowedReason,
            'user_message': 'Diretorio de trabalho fora da lista permitida para esta acao.',
          },
        ),
      );
    }

    return Success(
      AgentActionPathValidation(
        path: AgentActionValidatedPath(
          originalPath: originalPath,
          canonicalPath: canonicalPath,
        ),
      ),
    );
  }

  Future<Result<AgentActionPathValidation>> validateRequiredFile({
    required String actionId,
    required String field,
    required AgentActionPathReference path,
    required Set<String> allowedExtensions,
    Set<String> allowedDirectories = const <String>{},
    String phase = 'definition_validation',
    String invalidPathReason = AgentActionPathContextConstants.invalidPathReason,
    String notFoundReason = AgentActionPathContextConstants.fileNotFoundReason,
    String extensionNotAllowedReason = AgentActionPathContextConstants.fileExtensionNotAllowedReason,
    String notAllowedReason = AgentActionPathContextConstants.fileNotAllowedReason,
    String invalidPathUserMessage = 'Informe um arquivo valido para esta acao.',
    String notFoundUserMessage = 'Arquivo nao encontrado. Verifique se ele foi removido ou renomeado.',
    String extensionNotAllowedUserMessage = 'O arquivo precisa usar uma extensao permitida para esta acao.',
    String notAllowedUserMessage = 'Arquivo fora da lista permitida para esta acao.',
    bool? requireLaunchAccess,
    bool enforceWorkingDirectoryAllowlist = true,
  }) async {
    if (enforceWorkingDirectoryAllowlist &&
        allowedDirectories.isEmpty &&
        _allowlistValidator.isProductionProfile()) {
      return Failure(
        _allowlistValidator.validateProductionWorkingDirectoryAllowlist(
          actionId: actionId,
          pathPolicy: AgentActionPathPolicy(allowedWorkingDirectories: allowedDirectories),
          phase: phase,
        )!,
      );
    }

    final originalPath = path.displayPath.trim();
    if (originalPath.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Required file path cannot be empty.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'reason': invalidPathReason,
            'user_message': invalidPathUserMessage,
          },
        ),
      );
    }

    final extension = extensionOf(originalPath);
    if (!AgentActionPathValidationHelpers.allowsExtension(
      extension: extension,
      allowedExtensions: allowedExtensions,
    )) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'File extension is not allowed for this action.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'path': originalPath,
            'extension': extension ?? '',
            'allowed_extensions': allowedExtensions.toList(growable: false),
            'reason': extensionNotAllowedReason,
            'user_message': extensionNotAllowedUserMessage,
          },
        ),
      );
    }

    if (!await _fileExists(originalPath)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Required file was not found.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'path': originalPath,
            'reason': notFoundReason,
            'user_message': notFoundUserMessage,
          },
        ),
      );
    }

    final fileAccessFailure = await AgentActionPathAccessValidator.validateFileReadable(
      actionId: actionId,
      field: field,
      path: originalPath,
      phase: phase,
    );
    if (fileAccessFailure != null) {
      return Failure(fileAccessFailure);
    }

    if (requireLaunchAccess ?? false) {
      final launchFailure = _launchAccessValidator(
        actionId: actionId,
        field: field,
        path: originalPath,
        phase: phase,
      );
      if (launchFailure != null) {
        return Failure(launchFailure);
      }
    }

    final canonicalPath = await _canonicalizeFile(originalPath);
    if (enforceWorkingDirectoryAllowlist &&
        !await _allowlistValidator.isWithinAllowedDirectories(
          canonicalPath: canonicalPath,
          allowedDirectories: allowedDirectories,
        )) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Required file is outside the allowed directories for this action.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'path': originalPath,
            'canonical_path': canonicalPath,
            'reason': notAllowedReason,
            'user_message': notAllowedUserMessage,
          },
        ),
      );
    }

    final sizeBytes = await _fileLength(originalPath);
    final lastModifiedUtc = await AgentActionPathValidationHelpers.fileLastModifiedUtc(originalPath);
    return Success(
      AgentActionPathValidation(
        path: AgentActionValidatedPath(
          originalPath: originalPath,
          canonicalPath: canonicalPath,
          sizeBytes: sizeBytes,
          lastModifiedUtc: lastModifiedUtc,
        ),
      ),
    );
  }
}
