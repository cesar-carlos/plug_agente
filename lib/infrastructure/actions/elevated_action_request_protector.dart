import 'dart:convert';
import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_elevated_constants.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/elevated_action_directory_acl_hardener.dart';
import 'package:plug_agente/infrastructure/actions/elevated_protected_request.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

/// Writes short-lived elevated execution request files (execution id + nonce only).
class ElevatedActionRequestProtector {
  ElevatedActionRequestProtector({
    required GlobalStorageContext storageContext,
    Uuid? uuid,
    DateTime Function()? now,
    ElevatedActionDirectoryAclHardener? directoryAclHardener,
  }) : _storageContext = storageContext,
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now,
       _directoryAclHardener = directoryAclHardener ?? ElevatedActionDirectoryAclHardener();

  final GlobalStorageContext _storageContext;
  final Uuid _uuid;
  final DateTime Function() _now;
  final ElevatedActionDirectoryAclHardener _directoryAclHardener;

  Future<Result<ElevatedProtectedRequest>> writeProtectedRequest({required String executionId}) async {
    final validation = _validateExecutionId(executionId);
    if (validation.isError()) {
      return Failure(validation.exceptionOrNull()!);
    }
    final trimmedId = executionId.trim();

    await _directoryAclHardener.ensureSecured(_storageContext.appDirectoryPath);

    final requestsDirectory = Directory(
      AgentActionElevatedConstants.requestsDirectoryPath(_storageContext.appDirectoryPath),
    );
    if (!requestsDirectory.existsSync()) {
      try {
        await requestsDirectory.create(recursive: true);
      } on IOException catch (error) {
        return Failure(
          _protectionFailure(
            message: 'Unable to create elevated request directory.',
            executionId: trimmedId,
            cause: error,
          ),
        );
      }
    }

    final requestPath = AgentActionElevatedConstants.requestFilePath(
      _storageContext.appDirectoryPath,
      trimmedId,
    );
    final createdAt = _now().toUtc();
    final payload = <String, Object?>{
      'version': AgentActionElevatedConstants.requestSchemaVersion,
      'executionId': trimmedId,
      'nonce': _uuid.v4(),
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': createdAt.add(AgentActionElevatedConstants.requestTtl).toIso8601String(),
    };

    try {
      final encoded = utf8.encode(jsonEncode(payload));
      final tempFile = File('$requestPath.tmp');
      await tempFile.writeAsBytes(encoded, flush: true);
      await tempFile.rename(requestPath);
      return Success(
        ElevatedProtectedRequest(
          executionId: trimmedId,
          nonce: payload['nonce']! as String,
          expiresAt: createdAt.add(AgentActionElevatedConstants.requestTtl),
          requestPath: requestPath,
        ),
      );
    } on IOException catch (error) {
      return Failure(
        _protectionFailure(
          message: 'Unable to write elevated execution request file.',
          executionId: trimmedId,
          cause: error,
        ),
      );
    }
  }

  Result<void> _validateExecutionId(String executionId) {
    final trimmed = executionId.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Elevated execution id cannot be blank.',
          context: {
            'reason': AgentActionGateConstants.elevatedRequestProtectionFailedReason,
            'field': 'executionId',
          },
        ),
      );
    }
    if (trimmed.contains('..') || trimmed.contains('/') || trimmed.contains(r'\')) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Elevated execution id contains invalid path characters.',
          context: {
            'executionId': trimmed,
            'reason': AgentActionGateConstants.elevatedRequestProtectionFailedReason,
          },
        ),
      );
    }
    return const Success(unit);
  }

  ActionRuntimeFailure _protectionFailure({
    required String message,
    required String executionId,
    required Object cause,
  }) {
    return ActionRuntimeFailure.withContext(
      message: message,
      code: AgentActionFailureCode.elevatedRequestProtectionFailed,
      cause: cause,
      context: {
        'execution_id': executionId,
        'reason': AgentActionGateConstants.elevatedRequestProtectionFailedReason,
        'user_message': 'Nao foi possivel preparar a solicitacao para o executor elevado.',
      },
    );
  }
}
