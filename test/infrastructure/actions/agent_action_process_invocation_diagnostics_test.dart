import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_normalizer.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_invocation_diagnostics.dart';

void main() {
  group('AgentActionProcessInvocationDiagnostics', () {
    const invocation = AgentActionCommandInvocation(
      executable: 'cmd.exe',
      arguments: <String>['/C', 'echo secret-token'],
      runInShell: false,
      mode: ProcessStartMode.normal,
      redactedPreview: 'cmd.exe /C [REDACTED_COMMAND]',
      normalizedCommandLength: 16,
    );

    test('should keep normalized preview when output redaction is enabled', () {
      const capturePolicy = AgentActionCapturePolicy();

      expect(
        AgentActionProcessInvocationDiagnostics.logSafeCommandPreview(
          invocation: invocation,
          capturePolicy: capturePolicy,
        ),
        'cmd.exe /C [REDACTED_COMMAND]',
      );
    });

    test('should still avoid raw command text when output redaction is disabled', () {
      const capturePolicy = AgentActionCapturePolicy(redactBeforePersisting: false);

      expect(
        AgentActionProcessInvocationDiagnostics.logSafeCommandPreview(
          invocation: invocation,
          capturePolicy: capturePolicy,
        ),
        'cmd.exe /C [REDACTED_COMMAND]',
      );
    });
  });
}
