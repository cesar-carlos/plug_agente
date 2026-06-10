import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_context_file_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_existence_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_production_allowlist_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_snapshot_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_helpers.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_types.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

export 'agent_action_path_validation_types.dart';

class ActionPathValidator {
  factory ActionPathValidator({
    AgentActionPathExists? fileExists,
    AgentActionPathExists? directoryExists,
    AgentActionPathCanonicalizer? canonicalizeFile,
    AgentActionPathCanonicalizer? canonicalizeDirectory,
    AgentActionFileLengthResolver? fileLength,
    AgentActionFileTextReader? readText,
    AgentActionLaunchAccessValidator? launchAccessValidator,
    AgentActionProductionProfileResolver? isProductionProfile,
  }) {
    final resolvedCanonicalizeDirectory =
        canonicalizeDirectory ?? AgentActionPathValidationHelpers.defaultCanonicalizeDirectory;
    final resolvedFileExists = fileExists ?? AgentActionPathValidationHelpers.defaultFileExists;
    final resolvedDirectoryExists = directoryExists ?? AgentActionPathValidationHelpers.defaultDirectoryExists;
    final resolvedCanonicalizeFile = canonicalizeFile ?? AgentActionPathValidationHelpers.defaultCanonicalizeFile;
    final resolvedFileLength = fileLength ?? AgentActionPathValidationHelpers.defaultFileLength;
    final resolvedReadText = readText ?? AgentActionPathValidationHelpers.defaultReadText;
    final resolvedLaunchAccessValidator =
        launchAccessValidator ?? WindowsExecutableLaunchAccessChecker.validateLaunchAccess;

    final allowlistValidator = AgentActionPathProductionAllowlistValidator(
      canonicalizeDirectory: resolvedCanonicalizeDirectory,
      isProductionProfile: isProductionProfile,
    );

    return ActionPathValidator._(
      allowlistValidator: allowlistValidator,
      existenceValidator: AgentActionPathExistenceValidator(
        fileExists: resolvedFileExists,
        directoryExists: resolvedDirectoryExists,
        canonicalizeFile: resolvedCanonicalizeFile,
        canonicalizeDirectory: resolvedCanonicalizeDirectory,
        fileLength: resolvedFileLength,
        launchAccessValidator: resolvedLaunchAccessValidator,
        allowlistValidator: allowlistValidator,
      ),
      contextFileValidator: AgentActionContextFileValidator(
        fileExists: resolvedFileExists,
        canonicalizeFile: resolvedCanonicalizeFile,
        fileLength: resolvedFileLength,
        readText: resolvedReadText,
        allowlistValidator: allowlistValidator,
      ),
    );
  }

  const ActionPathValidator._({
    required AgentActionPathProductionAllowlistValidator allowlistValidator,
    required AgentActionPathExistenceValidator existenceValidator,
    required AgentActionContextFileValidator contextFileValidator,
  }) : _allowlistValidator = allowlistValidator,
       _existenceValidator = existenceValidator,
       _contextFileValidator = contextFileValidator;

  final AgentActionPathProductionAllowlistValidator _allowlistValidator;
  final AgentActionPathExistenceValidator _existenceValidator;
  final AgentActionContextFileValidator _contextFileValidator;

  ActionValidationFailure? validateProductionWorkingDirectoryAllowlist({
    required String actionId,
    required AgentActionPathPolicy pathPolicy,
    required String phase,
  }) {
    return _allowlistValidator.validateProductionWorkingDirectoryAllowlist(
      actionId: actionId,
      pathPolicy: pathPolicy,
      phase: phase,
    );
  }

  Future<Result<AgentActionPathValidation>> validateWorkingDirectory({
    required String actionId,
    required AgentActionPathReference? path,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String phase = 'definition_validation',
  }) {
    return _existenceValidator.validateWorkingDirectory(
      actionId: actionId,
      path: path,
      pathPolicy: pathPolicy,
      phase: phase,
    );
  }

  Future<Result<AgentActionPathValidation>> validateContextFile({
    required String actionId,
    required String? contextPath,
    required AgentActionContextPolicy policy,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String phase = 'execution_preflight',
  }) {
    return _contextFileValidator.validateContextFile(
      actionId: actionId,
      contextPath: contextPath,
      policy: policy,
      pathPolicy: pathPolicy,
      phase: phase,
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
  }) {
    return _existenceValidator.validateRequiredFile(
      actionId: actionId,
      field: field,
      path: path,
      allowedExtensions: allowedExtensions,
      allowedDirectories: allowedDirectories,
      phase: phase,
      invalidPathReason: invalidPathReason,
      notFoundReason: notFoundReason,
      extensionNotAllowedReason: extensionNotAllowedReason,
      notAllowedReason: notAllowedReason,
      invalidPathUserMessage: invalidPathUserMessage,
      notFoundUserMessage: notFoundUserMessage,
      extensionNotAllowedUserMessage: extensionNotAllowedUserMessage,
      notAllowedUserMessage: notAllowedUserMessage,
      requireLaunchAccess: requireLaunchAccess,
      enforceWorkingDirectoryAllowlist: enforceWorkingDirectoryAllowlist,
    );
  }

  Result<PathSnapshotCheck> ensurePathSnapshotMatchesCurrent({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    String phase = 'execution_preflight',
  }) {
    return AgentActionPathSnapshotValidator.ensurePathSnapshotMatchesCurrent(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      phase: phase,
    );
  }

  Result<PathSnapshotCheck> ensureValidationHashMatchesCurrent({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    String phase = 'execution_preflight',
  }) {
    return AgentActionPathSnapshotValidator.ensureValidationHashMatchesCurrent(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      phase: phase,
    );
  }

  Result<void> guardPathSnapshot({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    Map<String, Object?>? diagnostics,
    String phase = 'execution_preflight',
  }) {
    return AgentActionPathSnapshotValidator.guardPathSnapshot(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      diagnostics: diagnostics,
      phase: phase,
    );
  }

  static void appendPathSnapshotWarningsToDiagnostics({
    required Map<String, Object?> diagnostics,
    required List<Map<String, Object?>> warnings,
  }) {
    AgentActionPathSnapshotValidator.appendPathSnapshotWarningsToDiagnostics(
      diagnostics: diagnostics,
      warnings: warnings,
    );
  }
}
