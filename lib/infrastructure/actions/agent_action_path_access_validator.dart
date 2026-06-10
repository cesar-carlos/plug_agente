import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';

abstract final class AgentActionPathAccessValidator {
  static Future<ActionValidationFailure?> validateFileReadable({
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
      return permissionDeniedFailure(
        actionId: actionId,
        field: field,
        path: path,
        phase: phase,
        cause: error,
        isDirectory: false,
      );
    }
  }

  static Future<ActionValidationFailure?> validateDirectoryReadable({
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
      return permissionDeniedFailure(
        actionId: actionId,
        field: field,
        path: path,
        phase: phase,
        cause: error,
        isDirectory: true,
      );
    }
  }

  static ActionValidationFailure? permissionDeniedFailure({
    required String actionId,
    required String field,
    required String path,
    required String phase,
    required FileSystemException cause,
    required bool isDirectory,
  }) {
    if (!isAccessDenied(cause)) {
      return null;
    }

    return ActionValidationFailure.withContext(
      message: isDirectory ? 'Working directory is not readable.' : 'Required file is not readable.',
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

  static bool isAccessDenied(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == null) {
      return false;
    }

    // Windows ERROR_ACCESS_DENIED (5); Unix EACCES (13).
    return code == 5 || code == 13;
  }
}
