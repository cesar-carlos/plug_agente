import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:plug_agente/core/constants/agent_action_path_context_constants.dart';
import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/utils/path_extension.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_path_normalizer.dart';
import 'package:win32/win32.dart';

/// Best-effort Windows check that the agent process can launch a PE executable.
abstract final class WindowsExecutableLaunchAccessChecker {
  static const Set<String> launchExtensions = <String>{'.exe', '.com'};

  static bool shouldValidateLaunchAccess({
    required String phase,
    required String? extension,
  }) {
    return phase == AgentActionProcessConstants.executionPreflightPhase && extensionRequiresLaunchAccess(extension);
  }

  static bool shouldValidateLaunchAccessForPath({
    required String phase,
    required String path,
  }) {
    return shouldValidateLaunchAccess(phase: phase, extension: extensionOf(path));
  }

  static bool extensionRequiresLaunchAccess(String? extension) {
    if (extension == null || extension.isEmpty) {
      return false;
    }

    final normalized = extension.trim().toLowerCase();
    return launchExtensions.contains(
      normalized.startsWith('.') ? normalized : '.$normalized',
    );
  }

  static ActionValidationFailure? validateLaunchAccess({
    required String actionId,
    required String field,
    required String path,
    required String phase,
  }) {
    if (!Platform.isWindows || !extensionRequiresLaunchAccess(extensionOf(path))) {
      return null;
    }

    final ioPath = WindowsActionPathNormalizer.forLocalIo(path);
    final pathPtr = ioPath.toNativeUtf16();
    try {
      final handle = CreateFile(
        pathPtr,
        GENERIC_READ | GENERIC_EXECUTE,
        FILE_SHARE_READ,
        nullptr,
        OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL,
        NULL,
      );
      if (handle == INVALID_HANDLE_VALUE) {
        final errorCode = GetLastError();
        if (errorCode == ERROR_ACCESS_DENIED) {
          return ActionValidationFailure.withContext(
            message: 'Executable file cannot be launched with current permissions.',
            code: AgentActionFailureCode.pathPermissionDenied,
            context: {
              'action_id': actionId,
              'field': field,
              'phase': phase,
              'path': path,
              'os_error_code': errorCode,
              'reason': AgentActionPathContextConstants.pathExecutePermissionDeniedReason,
              'user_message':
                  'Sem permissao para executar o arquivo informado. Verifique as permissoes do usuario do agente.',
            },
          );
        }

        return ActionValidationFailure.withContext(
          message: 'Executable file could not be opened for launch preflight.',
          context: {
            'action_id': actionId,
            'field': field,
            'phase': phase,
            'path': path,
            'os_error_code': errorCode,
            'reason': AgentActionPathContextConstants.pathLaunchProbeFailedReason,
            'user_message': 'Nao foi possivel validar o executavel antes de iniciar o processo.',
          },
        );
      }

      CloseHandle(handle);
      return null;
    } finally {
      calloc.free(pathPtr);
    }
  }
}
