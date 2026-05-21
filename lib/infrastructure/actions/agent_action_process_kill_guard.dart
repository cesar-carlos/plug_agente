import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_process_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_identity_verifier.dart';

/// Shared validation before killing a locally tracked subprocess.
abstract final class AgentActionProcessKillGuard {
  static ActionFailure? validateBeforeKill({
    required String executionId,
    required Process process,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) {
    if (expectedPid != null && process.pid != expectedPid) {
      return ActionRuntimeFailure.withContext(
        message: 'Action execution process PID does not match the active process.',
        code: AgentActionFailureCode.processIdMismatch,
        context: {
          'execution_id': executionId,
          'expected_pid': expectedPid,
          'actual_pid': process.pid,
          'reason': AgentActionProcessConstants.pidMismatchReason,
          'user_message': 'O processo ativo nao corresponde ao PID salvo nesta execucao.',
        },
      );
    }

    return WindowsProcessIdentityVerifier.verify(
      executionId: executionId,
      pid: process.pid,
      expectedExecutable: expectedProcessExecutable,
      expectedStartedAt: expectedProcessStartedAt,
    );
  }
}
