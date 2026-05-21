import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_identity_verifier.dart';
import 'package:win32/win32.dart';

/// Kills the main process tracked for an action execution with stable failure mapping.
abstract final class AgentActionProcessKiller {
  /// Returns `null` when [Process.kill] succeeded.
  static ActionFailure? killMainProcess({
    required String executionId,
    required Process process,
  }) {
    try {
      if (process.kill()) {
        return null;
      }
    } on ProcessException catch (error) {
      if (_isKillPermissionDeniedOnCurrentPlatform(process.pid)) {
        return _killPermissionDenied(executionId: executionId, pid: process.pid, cause: error);
      }
      return _killFailed(executionId: executionId, pid: process.pid, cause: error);
    }

    if (_isKillPermissionDeniedOnCurrentPlatform(process.pid)) {
      return _killPermissionDenied(executionId: executionId, pid: process.pid);
    }

    return _killFailed(executionId: executionId, pid: process.pid);
  }

  /// Best-effort kill by [pid] after restart when identity checks pass (or are skipped).
  ///
  /// Returns `false` when the PID is invalid, identity does not match, or termination fails.
  static bool tryKillOrphanByPid({
    required String executionId,
    required int pid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) {
    if (pid <= 0) {
      return false;
    }

    final identityFailure = WindowsProcessIdentityVerifier.verify(
      executionId: executionId,
      pid: pid,
      expectedExecutable: expectedProcessExecutable,
      expectedStartedAt: expectedProcessStartedAt,
    );
    if (identityFailure != null) {
      return false;
    }

    if (Platform.isWindows) {
      return _windowsTerminateProcess(pid);
    }

    try {
      return Process.killPid(pid);
    } on ProcessException {
      return false;
    }
  }

  static bool isOsAccessDeniedErrorCode(int? errorCode) {
    if (errorCode == null) {
      return false;
    }

    // Windows ERROR_ACCESS_DENIED (5); Unix EACCES (13).
    return errorCode == ERROR_ACCESS_DENIED || errorCode == 13;
  }

  static bool _isKillPermissionDeniedOnCurrentPlatform(int pid) {
    if (!Platform.isWindows) {
      return false;
    }

    return _windowsTerminateAccessErrorCode(pid) == ERROR_ACCESS_DENIED;
  }

  static bool _windowsTerminateProcess(int pid) {
    final handle = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (handle == 0 || handle == INVALID_HANDLE_VALUE) {
      return false;
    }

    try {
      return TerminateProcess(handle, 1) != 0;
    } finally {
      CloseHandle(handle);
    }
  }

  static int? _windowsTerminateAccessErrorCode(int pid) {
    if (pid <= 0) {
      return null;
    }

    final handle = OpenProcess(PROCESS_TERMINATE, FALSE, pid);
    if (handle != 0 && handle != INVALID_HANDLE_VALUE) {
      CloseHandle(handle);
      return null;
    }

    return GetLastError();
  }

  static ActionFailure _killPermissionDenied({
    required String executionId,
    required int pid,
    Object? cause,
  }) {
    return ActionRuntimeFailure.withContext(
      message: 'Insufficient permission to terminate the action execution process.',
      code: AgentActionFailureCode.killPermissionDenied,
      cause: cause,
      context: {
        'execution_id': executionId,
        'pid': pid,
        'reason': AgentActionProcessConstants.killPermissionDeniedReason,
        'user_message':
            'Sem permissao para finalizar o processo principal. Execute o agente com privilegios adequados ou cancele pela conta que iniciou o processo.',
      },
    );
  }

  static ActionFailure _killFailed({
    required String executionId,
    required int pid,
    Object? cause,
  }) {
    return ActionRuntimeFailure.withContext(
      message: 'Failed to kill action execution process.',
      code: AgentActionFailureCode.killFailed,
      cause: cause,
      context: {
        'execution_id': executionId,
        'pid': pid,
        'reason': AgentActionRpcConstants.agentActionCancelKillFailedErrorReason,
        'user_message': 'Nao foi possivel finalizar o processo principal desta execucao.',
      },
    );
  }
}
