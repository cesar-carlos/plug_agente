import 'package:plug_agente/domain/actions/action_execution.dart' show AgentActionExecution;
import 'package:plug_agente/domain/actions/actions.dart' show AgentActionExecution;
import 'package:plug_agente/domain/domain.dart' show AgentActionExecution;

/// Stable `failure.context['reason']` and `phase` for subprocess lifecycle and invalid action configuration.
abstract final class AgentActionProcessConstants {
  static const String definitionValidationPhase = 'definition_validation';

  static const String executionPreflightPhase = 'execution_preflight';

  static const String elevatedSubmitPhase = 'elevated_submit';

  static const String bootstrapReconciliationPhase = 'bootstrap_reconciliation';

  static const String invalidActionConfigReason = 'invalid_action_config';

  static const String processStartFailedReason = 'process_start_failed';

  static const String processRuntimeErrorReason = 'process_runtime_error';

  static const String processNotActiveReason = 'process_not_active';

  static const String killPermissionDeniedReason = 'kill_permission_denied';

  static const String pidMismatchReason = 'pid_mismatch';

  static const String processIdentityMismatchReason = 'process_identity_mismatch';

  static const String processIdentityUnavailableReason = 'process_identity_unavailable';

  /// Allowed skew between persisted [AgentActionExecution.processStartedAt] and OS creation time.
  static const Duration processIdentityStartedAtTolerance = Duration(seconds: 30);

  static const String stdinCloseFailedReason = 'stdin_close_failed';

  static const String stdinWriteFailedReason = 'stdin_write_failed';

  /// Runtime parameter key for stdin injection mode (`AgentActionContextInjectionMode.stdin`).
  static const String stdinRuntimeParameterKey = 'stdin';

  /// Windows shell used for free-form `commandLine` and structured `.bat`/`.cmd` wrappers.
  static const String windowsCmdExecutable = 'cmd.exe';

  static const String cmdExecuteOnceSwitch = '/C';
}
