import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_execution_support_export.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  group('AgentActionExecutionSupportExport', () {
    const export = AgentActionExecutionSupportExport();

    test('should emit redacted support json with diagnostics metadata when execution failed', () {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.failed,
        requestedAt: DateTime.utc(2026, 5, 15, 8, 30),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-1',
        requestedBy: 'hub-user',
        traceId: 'trace-1',
        processCommandPreview: 'cmd.exe /C [REDACTED_COMMAND]',
        definitionSnapshotHash: 'sha256:def',
        contextHash: 'sha256:ctx',
        redactionApplied: true,
        failureCode: AgentActionFailureCode.exitCodeRejected,
        failurePhase: 'process_exit',
        stdoutText: 'safe stdout',
        stderrText: 'safe stderr',
        stderrTruncated: true,
      );

      final decoded = jsonDecode(export.buildJson(execution)) as Map<String, dynamic>;

      expect(decoded['support_schema'], 'plug_agente.support.v1');
      expect(decoded['support_category'], 'agent_action_execution');
      expect(decoded['execution_id'], 'execution-1');
      expect(decoded['failure_code'], AgentActionFailureCode.exitCodeRejected);
      expect(decoded['failure_phase'], 'process_exit');
      expect(decoded['corrective_action'], 'review_exit_code');
      expect(decoded['process_command_preview'], 'cmd.exe /C [REDACTED_COMMAND]');
      expect(decoded['stdout'], 'safe stdout');
      expect(decoded['stderr'], 'safe stderr');
      expect(decoded['stderr_truncated'], isTrue);
      expect(decoded['redaction_applied'], isTrue);
      expect(decoded.containsKey('password'), isFalse);
    });
  });
}
