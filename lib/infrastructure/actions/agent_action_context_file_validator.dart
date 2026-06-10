import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_access_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_production_allowlist_validator.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_helpers.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_path_validation_types.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionContextFileValidator {
  AgentActionContextFileValidator({
    required AgentActionPathExists fileExists,
    required AgentActionPathCanonicalizer canonicalizeFile,
    required AgentActionFileLengthResolver fileLength,
    required AgentActionFileTextReader readText,
    required AgentActionPathProductionAllowlistValidator allowlistValidator,
  }) : _fileExists = fileExists,
       _canonicalizeFile = canonicalizeFile,
       _fileLength = fileLength,
       _readText = readText,
       _allowlistValidator = allowlistValidator;

  final AgentActionPathExists _fileExists;
  final AgentActionPathCanonicalizer _canonicalizeFile;
  final AgentActionFileLengthResolver _fileLength;
  final AgentActionFileTextReader _readText;
  final AgentActionPathProductionAllowlistValidator _allowlistValidator;

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

    final extension = extensionOf(trimmedPath);
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
    if (!await _allowlistValidator.isWithinAllowedDirectories(
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
      final permissionFailure = AgentActionPathAccessValidator.permissionDeniedFailure(
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

    final lastModifiedUtc = await AgentActionPathValidationHelpers.fileLastModifiedUtc(trimmedPath);
    return Success(
      AgentActionPathValidation(
        path: AgentActionValidatedPath(
          originalPath: trimmedPath,
          canonicalPath: canonicalPath,
          sizeBytes: sizeBytes,
          lastModifiedUtc: lastModifiedUtc,
          contentHash: AgentActionPathValidationHelpers.hashContent(content),
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
}
