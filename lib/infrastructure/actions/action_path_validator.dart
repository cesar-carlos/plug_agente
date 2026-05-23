import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:json_schema/json_schema.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_path_prod_defaults_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/windows_executable_launch_access_checker.dart';
import 'package:result_dart/result_dart.dart';

typedef AgentActionPathExists = Future<bool> Function(String path);
typedef AgentActionPathCanonicalizer = Future<String> Function(String path);
typedef AgentActionFileLengthResolver = Future<int> Function(String path);
typedef AgentActionFileTextReader = Future<String> Function(String path);
typedef AgentActionLaunchAccessValidator =
    ActionValidationFailure? Function({
      required String actionId,
      required String field,
      required String path,
      required String phase,
    });

class AgentActionValidatedPath {
  const AgentActionValidatedPath({
    required this.originalPath,
    required this.canonicalPath,
    this.sizeBytes,
    this.lastModifiedUtc,
    this.contentHash,
  });

  final String originalPath;
  final String canonicalPath;
  final int? sizeBytes;
  final DateTime? lastModifiedUtc;
  final String? contentHash;
}

class AgentActionPathValidation {
  const AgentActionPathValidation({
    this.path,
  });

  const AgentActionPathValidation.notProvided() : path = null;

  final AgentActionValidatedPath? path;

  bool get hasPath => path != null;
}

class PathSnapshotCheck {
  const PathSnapshotCheck.unchanged() : warningMessage = null;

  const PathSnapshotCheck.warning(this.warningMessage);

  final String? warningMessage;

  bool get hasWarning => warningMessage != null && warningMessage!.isNotEmpty;
}

typedef AgentActionProductionProfileResolver = bool Function();

class ActionPathValidator {
  ActionPathValidator({
    AgentActionPathExists? fileExists,
    AgentActionPathExists? directoryExists,
    AgentActionPathCanonicalizer? canonicalizeFile,
    AgentActionPathCanonicalizer? canonicalizeDirectory,
    AgentActionFileLengthResolver? fileLength,
    AgentActionFileTextReader? readText,
    AgentActionLaunchAccessValidator? launchAccessValidator,
    AgentActionProductionProfileResolver? isProductionProfile,
  }) : _fileExists = fileExists ?? _defaultFileExists,
       _directoryExists = directoryExists ?? _defaultDirectoryExists,
       _canonicalizeFile = canonicalizeFile ?? _defaultCanonicalizeFile,
       _canonicalizeDirectory = canonicalizeDirectory ?? _defaultCanonicalizeDirectory,
       _fileLength = fileLength ?? _defaultFileLength,
       _readText = readText ?? _defaultReadText,
       _launchAccessValidator =
           launchAccessValidator ?? WindowsExecutableLaunchAccessChecker.validateLaunchAccess,
       _isProductionProfile = isProductionProfile ?? _defaultIsProductionProfile;

  final AgentActionPathExists _fileExists;
  final AgentActionPathExists _directoryExists;
  final AgentActionPathCanonicalizer _canonicalizeFile;
  final AgentActionPathCanonicalizer _canonicalizeDirectory;
  final AgentActionFileLengthResolver _fileLength;
  final AgentActionFileTextReader _readText;
  final AgentActionLaunchAccessValidator _launchAccessValidator;
  final AgentActionProductionProfileResolver _isProductionProfile;

  static bool _defaultIsProductionProfile() {
    final raw = AppEnvironment.get(AgentActionGateConstants.operationalProfileEnvironmentKey);
    return AgentActionPathProdDefaultsConstants.isProductionProfile(raw);
  }

  String? get _currentOperationalProfile {
    return AppEnvironment.get(AgentActionGateConstants.operationalProfileEnvironmentKey);
  }

  ActionValidationFailure? validateProductionWorkingDirectoryAllowlist({
    required String actionId,
    required AgentActionPathPolicy pathPolicy,
    required String phase,
  }) {
    if (!_isProductionProfile()) {
      return null;
    }
    if (_hasNonBlankAllowlist(pathPolicy.allowedWorkingDirectories)) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: 'Production profile requires explicit working directory allowlist.',
      context: {
        'action_id': actionId,
        'field': 'path.allowedWorkingDirectories',
        'phase': phase,
        'reason': AgentActionPathContextConstants.productionPathAllowlistRequiredReason,
        'operational_profile': _currentOperationalProfile,
        'user_message': AgentActionPathProdDefaultsConstants.productionAllowlistRequiredUserMessage,
      },
    );
  }

  Future<Result<AgentActionPathValidation>> validateWorkingDirectory({
    required String actionId,
    required AgentActionPathReference? path,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String phase = 'definition_validation',
  }) async {
    final productionAllowlistFailure = validateProductionWorkingDirectoryAllowlist(
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

    final directoryAccessFailure = await _validateDirectoryReadable(
      actionId: actionId,
      field: 'workingDirectory',
      path: originalPath,
      phase: phase,
    );
    if (directoryAccessFailure != null) {
      return Failure(directoryAccessFailure);
    }

    final canonicalPath = await _canonicalizeDirectory(originalPath);
    if (!await _isWithinAllowedDirectories(
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

  Future<Result<AgentActionPathValidation>> validateContextFile({
    required String actionId,
    required String? contextPath,
    required AgentActionContextPolicy policy,
    AgentActionPathPolicy pathPolicy = const AgentActionPathPolicy(),
    String phase = 'execution_preflight',
  }) async {
    final trimmedPath = contextPath?.trim();
    if (trimmedPath == null) {
      return const Success(AgentActionPathValidation.notProvided());
    }
    if (trimmedPath.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Context file path cannot be empty.',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'reason': AgentActionValidationConstants.invalidContextPathReason,
            'user_message': 'Informe um arquivo de contexto valido ou remova este campo.',
          },
        ),
      );
    }

    final extension = _extensionOf(trimmedPath);
    if (extension == null || !policy.allowsExtension(extension)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Context file extension is not allowed for this action.',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'extension': extension ?? '',
            'allowed_extensions': policy.allowedContextExtensions.toList(growable: false),
            'reason': AgentActionPathContextConstants.contextExtensionNotAllowedReason,
            'user_message': 'O arquivo de contexto precisa usar uma extensao permitida para esta acao.',
          },
        ),
      );
    }

    if (!await _fileExists(trimmedPath)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Context file was not found.',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'path': trimmedPath,
            'reason': AgentActionPathContextConstants.contextFileNotFoundReason,
            'user_message': 'Arquivo de contexto nao encontrado. Verifique se ele foi removido ou renomeado.',
          },
        ),
      );
    }

    final canonicalPath = await _canonicalizeFile(trimmedPath);
    if (!await _isWithinAllowedDirectories(
      canonicalPath: canonicalPath,
      allowedDirectories: pathPolicy.allowedContextDirectories,
    )) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Context file is outside the allowed directories for this action.',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'path': trimmedPath,
            'canonical_path': canonicalPath,
            'reason': AgentActionPathContextConstants.contextFileNotAllowedReason,
            'user_message': 'Arquivo de contexto fora da lista permitida para esta acao.',
          },
        ),
      );
    }

    final sizeBytes = await _fileLength(trimmedPath);
    if (sizeBytes > policy.maxContextBytes) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Context file is larger than the action limit.',
          context: {
            'action_id': actionId,
            'field': 'contextPath',
            'phase': phase,
            'size_bytes': sizeBytes,
            'max_bytes': policy.maxContextBytes,
            'reason': AgentActionPathContextConstants.contextFileTooLargeReason,
            'user_message': 'Arquivo de contexto maior que o limite permitido para esta acao.',
          },
        ),
      );
    }

    String content;
    try {
      content = await _readText(trimmedPath);
    } on FileSystemException catch (error) {
      final permissionFailure = _permissionDeniedFailure(
        actionId: actionId,
        field: 'contextPath',
        path: trimmedPath,
        phase: phase,
        cause: error,
        isDirectory: false,
      );
      if (permissionFailure != null) {
        return Failure(permissionFailure);
      }
      rethrow;
    }
    if (extension == '.json') {
      final jsonValidation = _validateJsonContent(
        actionId: actionId,
        path: trimmedPath,
        policy: policy,
        content: content,
        phase: phase,
      );
      if (jsonValidation != null) {
        return Failure(jsonValidation);
      }
    }

    final lastModifiedUtc = await _fileLastModifiedUtc(trimmedPath);
    return Success(
      AgentActionPathValidation(
        path: AgentActionValidatedPath(
          originalPath: trimmedPath,
          canonicalPath: canonicalPath,
          sizeBytes: sizeBytes,
          lastModifiedUtc: lastModifiedUtc,
          contentHash: _hashContent(content),
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
  }) async {
    if (allowedDirectories.isEmpty && _isProductionProfile()) {
      return Failure(
        validateProductionWorkingDirectoryAllowlist(
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

    final extension = _extensionOf(originalPath);
    if (!_allowsExtension(extension: extension, allowedExtensions: allowedExtensions)) {
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

    final fileAccessFailure = await _validateFileReadable(
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
    if (!await _isWithinAllowedDirectories(
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
    final lastModifiedUtc = await _fileLastModifiedUtc(originalPath);
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

  ActionValidationFailure? _validateJsonContent({
    required String actionId,
    required String path,
    required AgentActionContextPolicy policy,
    required String content,
    required String phase,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (error) {
      return ActionValidationFailure.withContext(
        message: 'Context JSON file is invalid.',
        cause: error,
        context: {
          'action_id': actionId,
          'field': 'contextPath',
          'phase': phase,
          'path': path,
          'reason': AgentActionPathContextConstants.invalidContextJsonReason,
          'user_message': 'Arquivo de contexto JSON invalido. Corrija o JSON e tente novamente.',
        },
      );
    }

    final schemaDefinition = policy.contextJsonSchema;
    if (schemaDefinition == null) {
      return null;
    }

    final JsonSchema schema;
    try {
      schema = JsonSchema.create(schemaDefinition);
    } on FormatException catch (error) {
      return _invalidJsonSchemaDefinitionFailure(
        actionId: actionId,
        path: path,
        error: error,
        phase: phase,
      );
    }

    final validation = schema.validate(decoded, validateFormats: false);
    if (validation.isValid) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: 'Context JSON file does not match the action schema.',
      context: {
        'action_id': actionId,
        'field': 'contextPath',
        'phase': phase,
        'path': path,
        'reason': AgentActionPathContextConstants.invalidContextJsonSchemaReason,
        'schema_error_count': validation.errors.length,
        'schema_errors': validation.errors
            .take(5)
            .map((error) => '${error.instancePath.isEmpty ? '# (root)' : error.instancePath}: ${error.message}')
            .toList(growable: false),
        'user_message': 'Arquivo de contexto JSON fora do formato esperado para esta acao.',
      },
    );
  }

  ActionValidationFailure _invalidJsonSchemaDefinitionFailure({
    required String actionId,
    required String path,
    required Object error,
    required String phase,
  }) {
    return ActionValidationFailure.withContext(
      message: 'Action context JSON schema is invalid.',
      cause: error,
      context: {
        'action_id': actionId,
        'field': 'contextJsonSchema',
        'phase': phase,
        'path': path,
        'reason': AgentActionValidationConstants.invalidContextJsonSchemaDefinitionReason,
        'user_message': 'O schema JSON configurado para esta acao e invalido.',
      },
    );
  }

  Result<PathSnapshotCheck> ensurePathSnapshotMatchesCurrent({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    String phase = 'execution_preflight',
  }) {
    final savedCanonicalPath = savedReference?.canonicalPath?.trim();
    if (savedCanonicalPath == null || savedCanonicalPath.isEmpty || currentPath == null) {
      return const Success(PathSnapshotCheck.unchanged());
    }

    if (_normalizePathForComparison(savedCanonicalPath) == _normalizePathForComparison(currentPath.canonicalPath)) {
      return const Success(PathSnapshotCheck.unchanged());
    }

    return _pathDriftResult(
      actionId: actionId,
      field: field,
      phase: phase,
      policy: savedReference!.effectivePathChangePolicy,
      reason: AgentActionPathContextConstants.pathChangedAfterSaveReason,
      userMessage:
          'O caminho salvo para esta acao mudou desde a validacao anterior. Revise a configuracao e salve novamente.',
      diagnostics: {
        'saved_canonical_path': savedCanonicalPath,
        'current_canonical_path': currentPath.canonicalPath,
      },
    );
  }

  Result<PathSnapshotCheck> ensureValidationHashMatchesCurrent({
    required String actionId,
    required String field,
    required AgentActionPathReference? savedReference,
    required AgentActionValidatedPath? currentPath,
    String phase = 'execution_preflight',
  }) {
    final savedHash = savedReference?.validationHash?.trim();
    final currentHash = currentPath?.contentHash?.trim();
    if (savedHash == null ||
        savedHash.isEmpty ||
        currentHash == null ||
        currentHash.isEmpty ||
        savedHash == currentHash) {
      return const Success(PathSnapshotCheck.unchanged());
    }

    return _pathDriftResult(
      actionId: actionId,
      field: field,
      phase: phase,
      policy: savedReference!.effectivePathChangePolicy,
      reason: AgentActionPathContextConstants.pathContentChangedAfterSaveReason,
      userMessage:
          'O conteudo do arquivo mudou desde a validacao anterior. Revise o arquivo ou atualize a definicao da acao.',
      diagnostics: {
        'saved_validation_hash': savedHash,
        'current_content_hash': currentHash,
      },
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
    final canonicalResult = ensurePathSnapshotMatchesCurrent(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      phase: phase,
    );
    if (canonicalResult.isError()) {
      return Failure(canonicalResult.exceptionOrNull()!);
    }
    _appendPathSnapshotWarning(
      diagnostics: diagnostics,
      field: field,
      check: canonicalResult.getOrThrow(),
    );

    final hashResult = ensureValidationHashMatchesCurrent(
      actionId: actionId,
      field: field,
      savedReference: savedReference,
      currentPath: currentPath,
      phase: phase,
    );
    if (hashResult.isError()) {
      return Failure(hashResult.exceptionOrNull()!);
    }
    _appendPathSnapshotWarning(
      diagnostics: diagnostics,
      field: field,
      check: hashResult.getOrThrow(),
      kind: 'content_hash',
    );

    return const Success(unit);
  }

  static void appendPathSnapshotWarningsToDiagnostics({
    required Map<String, Object?> diagnostics,
    required List<Map<String, Object?>> warnings,
  }) {
    if (warnings.isEmpty) {
      return;
    }

    final existing = diagnostics['path_snapshot_warnings'];
    if (existing is List) {
      diagnostics['path_snapshot_warnings'] = <Object?>[
        ...existing,
        ...warnings,
      ];
    } else {
      diagnostics['path_snapshot_warnings'] = warnings;
    }
  }

  Result<PathSnapshotCheck> _pathDriftResult({
    required String actionId,
    required String field,
    required String phase,
    required AgentActionPathChangePolicy policy,
    required String reason,
    required String userMessage,
    required Map<String, Object?> diagnostics,
  }) {
    return switch (policy) {
      AgentActionPathChangePolicy.allowChanged => const Success(PathSnapshotCheck.unchanged()),
      AgentActionPathChangePolicy.warnIfChanged => Success(
        PathSnapshotCheck.warning(userMessage),
      ),
      AgentActionPathChangePolicy.failIfChanged => Failure(
        ActionValidationFailure.withContext(
          message: 'Path validation snapshot does not match the current state.',
          code: AgentActionFailureCode.pathSnapshotMismatch,
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'reason': reason,
            'path_change_policy': policy.name,
            'user_message': userMessage,
            ...diagnostics,
          },
        ),
      ),
    };
  }

  void _appendPathSnapshotWarning({
    required Map<String, Object?>? diagnostics,
    required String field,
    required PathSnapshotCheck check,
    String kind = 'canonical_path',
  }) {
    if (diagnostics == null || !check.hasWarning) {
      return;
    }

    appendPathSnapshotWarningsToDiagnostics(
      diagnostics: diagnostics,
      warnings: [
        {
          'field': field,
          'kind': kind,
          'message': check.warningMessage,
        },
      ],
    );
  }

  String _hashContent(String content) {
    return 'sha256:${sha256.convert(utf8.encode(content))}';
  }

  String? _extensionOf(String path) {
    final lastSeparator = path.lastIndexOf(RegExp(r'[\\/]'));
    final fileName = lastSeparator >= 0 ? path.substring(lastSeparator + 1) : path;
    final dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length - 1) {
      return null;
    }

    return fileName.substring(dotIndex).toLowerCase();
  }

  Future<bool> _isWithinAllowedDirectories({
    required String canonicalPath,
    required Set<String> allowedDirectories,
  }) async {
    if (allowedDirectories.isEmpty) {
      if (_isProductionProfile()) {
        return false;
      }
      return true;
    }

    final normalizedPath = _normalizePathForComparison(canonicalPath);
    for (final allowedDirectory in allowedDirectories) {
      final trimmed = allowedDirectory.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      try {
        final canonicalAllowedDirectory = await _canonicalizeDirectory(trimmed);
        final normalizedAllowedDirectory = _normalizePathForComparison(
          canonicalAllowedDirectory,
        );
        if (normalizedPath == normalizedAllowedDirectory || normalizedPath.startsWith('$normalizedAllowedDirectory/')) {
          return true;
        }
      } on FileSystemException {
        continue;
      } on Exception {
        continue;
      }
    }

    return false;
  }

  String _normalizePathForComparison(String path) => WindowsActionPathNormalizer.normalizeForComparison(path);

  Future<ActionValidationFailure?> _validateFileReadable({
    required String actionId,
    required String field,
    required String path,
    required String phase,
  }) async {
    try {
      final ioPath = WindowsActionPathNormalizer.forLocalIo(path);
      final handle = await File(ioPath).open();
      await handle.close();
      return null;
    } on FileSystemException catch (error) {
      return _permissionDeniedFailure(
        actionId: actionId,
        field: field,
        path: path,
        phase: phase,
        cause: error,
        isDirectory: false,
      );
    }
  }

  Future<ActionValidationFailure?> _validateDirectoryReadable({
    required String actionId,
    required String field,
    required String path,
    required String phase,
  }) async {
    try {
      final ioPath = WindowsActionPathNormalizer.forLocalIo(path);
      await for (final _ in Directory(ioPath).list(followLinks: false)) {
        break;
      }
      return null;
    } on FileSystemException catch (error) {
      return _permissionDeniedFailure(
        actionId: actionId,
        field: field,
        path: path,
        phase: phase,
        cause: error,
        isDirectory: true,
      );
    }
  }

  ActionValidationFailure? _permissionDeniedFailure({
    required String actionId,
    required String field,
    required String path,
    required String phase,
    required FileSystemException cause,
    required bool isDirectory,
  }) {
    if (!_isAccessDenied(cause)) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: isDirectory
          ? 'Working directory is not readable.'
          : 'Required file is not readable.',
      code: AgentActionFailureCode.pathPermissionDenied,
      cause: cause,
      context: {
        'action_id': actionId,
        'field': field,
        'phase': phase,
        'path': path,
        'os_error_code': cause.osError?.errorCode,
        'reason': AgentActionPathContextConstants.pathPermissionDeniedReason,
        'user_message': isDirectory
            ? 'Sem permissao para acessar o diretorio de trabalho. Verifique as permissoes do usuario do agente.'
            : 'Sem permissao para ler o arquivo exigido por esta acao. Verifique as permissoes do usuario do agente.',
      },
    );
  }

  bool _isAccessDenied(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == null) {
      return false;
    }

    // Windows ERROR_ACCESS_DENIED (5); Unix EACCES (13).
    return code == 5 || code == 13;
  }

  static Future<bool> _defaultFileExists(String path) =>
      Future<bool>.value(WindowsActionPathNormalizer.fileExists(path));

  static Future<bool> _defaultDirectoryExists(String path) =>
      Future<bool>.value(WindowsActionPathNormalizer.directoryExists(path));

  static Future<String> _defaultCanonicalizeFile(String path) => WindowsActionPathNormalizer.canonicalizeFile(path);

  static Future<String> _defaultCanonicalizeDirectory(String path) =>
      WindowsActionPathNormalizer.canonicalizeDirectory(path);

  static Future<int> _defaultFileLength(String path) => WindowsActionPathNormalizer.fileLength(path);

  static Future<String> _defaultReadText(String path) => WindowsActionPathNormalizer.readText(path);

  Future<DateTime?> _fileLastModifiedUtc(String path) async {
    try {
      final ioPath = WindowsActionPathNormalizer.forLocalIo(path);
      return File(ioPath).lastModifiedSync().toUtc();
    } on FileSystemException {
      return null;
    }
  }

  bool _allowsExtension({
    required String? extension,
    required Set<String> allowedExtensions,
  }) {
    if (allowedExtensions.isEmpty) {
      return true;
    }
    if (extension == null || extension.isEmpty) {
      return false;
    }

    final normalizedExtension = extension.trim().toLowerCase();
    return allowedExtensions.any((candidate) {
      final normalizedCandidate = candidate.trim().toLowerCase();
      if (normalizedCandidate.isEmpty) {
        return false;
      }
      final candidateWithDot = normalizedCandidate.startsWith('.') ? normalizedCandidate : '.$normalizedCandidate';
      return normalizedExtension == candidateWithDot;
    });
  }

  bool _hasNonBlankAllowlist(Set<String> allowedDirectories) {
    for (final directory in allowedDirectories) {
      if (directory.trim().isNotEmpty) {
        return true;
      }
    }

    return false;
  }
}
