import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart' show AgentActionCommandInvocation;

/// Builds failure/runtime diagnostic maps without leaking raw shell commands.
abstract final class AgentActionProcessInvocationDiagnostics {
  static Map<String, Object?> forInvocation({
    required AgentActionCommandInvocation invocation,
    required AgentActionCapturePolicy capturePolicy,
  }) {
    return <String, Object?>{
      'executable': invocation.executable,
      'argument_count': invocation.arguments.length,
      'command_preview': logSafeCommandPreview(
        invocation: invocation,
        capturePolicy: capturePolicy,
      ),
      'run_in_shell': invocation.runInShell,
      'process_start_mode': invocation.mode.toString(),
    };
  }

  static String logSafeCommandPreview({
    required AgentActionCommandInvocation invocation,
    required AgentActionCapturePolicy capturePolicy,
  }) {
    if (capturePolicy.redactBeforePersisting) {
      return invocation.redactedPreview;
    }

    return logSafeCommandPreviewText(
      preview: invocation.redactedPreview,
      capturePolicy: capturePolicy,
    );
  }

  static String logSafeCommandPreviewText({
    required String preview,
    required AgentActionCapturePolicy capturePolicy,
  }) {
    if (capturePolicy.redactBeforePersisting) {
      return preview;
    }

    return const AgentActionRedactor().redactText(preview);
  }
}
