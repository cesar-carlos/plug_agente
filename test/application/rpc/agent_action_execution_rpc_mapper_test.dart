import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  group('agentActionExecutionToGetExecutionResult', () {
    test('should serialize execution timestamps as UTC ISO-8601', () {
      final execution = AgentActionExecution(
        id: 'exec-utc-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 19, 10, 30),
        source: AgentActionRequestSource.localUi,
        scheduledAt: DateTime.utc(2026, 5, 19, 10, 25),
        triggeredAt: DateTime.utc(2026, 5, 19, 10, 29),
        queueStartedAt: DateTime.utc(2026, 5, 19, 10, 29, 30),
        processStartedAt: DateTime.utc(2026, 5, 19, 10, 29, 45),
        finishedAt: DateTime.utc(2026, 5, 19, 10, 31),
        triggerId: 'trigger-1',
        triggerType: AgentActionTriggerType.daily,
      );

      final result = agentActionExecutionToGetExecutionResult(execution);

      expect(result['requested_at'], '2026-05-19T10:30:00.000Z');
      final trigger = result['trigger']! as Map<String, dynamic>;
      expect(trigger['scheduled_at'], '2026-05-19T10:25:00.000Z');
      expect(trigger['triggered_at'], '2026-05-19T10:29:00.000Z');
      final timestamps = result['timestamps']! as Map<String, dynamic>;
      expect(timestamps['queue_started_at'], '2026-05-19T10:29:30.000Z');
      expect(timestamps['process_started_at'], '2026-05-19T10:29:45.000Z');
      expect(timestamps['finished_at'], '2026-05-19T10:31:00.000Z');
    });

    test('should expose failure phase process metadata and corrective action', () {
      final execution = AgentActionExecution(
        id: 'exec-failed-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.failed,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 1),
        processStartedAt: DateTime.utc(2026, 5, 18, 14),
        failureCode: AgentActionFailureCode.runtimeError,
        failurePhase: 'start_process',
        failureMessage: 'Failed to start command line action process.',
        processExecutable: 'cmd.exe',
        processArgumentCount: 2,
        processCommandPreview: 'cmd.exe /C [REDACTED_COMMAND]',
        redactionApplied: true,
      );

      final result = agentActionExecutionToGetExecutionResult(execution);

      final process = result['process'] as Map<String, dynamic>;
      expect(process['executable'], 'cmd.exe');
      expect(process['argument_count'], 2);
      expect(process['command_preview'], 'cmd.exe /C [REDACTED_COMMAND]');

      final failure = result['failure'] as Map<String, dynamic>;
      expect(failure['code'], 'ACTION_RUNTIME_ERROR');
      expect(failure['phase'], 'start_process');
      expect(failure['message'], 'Failed to start command line action process.');
      expect(failure['corrective_action'], 'review_start_process');
    });

    test('should omit stdout text when exposeStdout is false', () {
      final execution = AgentActionExecution(
        id: 'exec-hidden-stdout',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        stdoutText: 'secret-ish output',
        redactionApplied: true,
      );

      final result = agentActionExecutionToGetExecutionResult(
        execution,
        exposeStdout: false,
      );

      final stdout = (result['output'] as Map<String, dynamic>)['stdout'] as Map<String, dynamic>;
      expect(stdout['captured'], isFalse);
      expect(stdout.containsKey('text'), isFalse);
    });

    test('should omit command preview and captured output when remote sanitization is required', () {
      final execution = AgentActionExecution(
        id: 'exec-remote-unsafe',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime.utc(2026, 5, 19, 10),
        source: AgentActionRequestSource.remoteHub,
        processCommandPreview: 'cmd.exe /C secret.exe',
        stdoutText: 'leaked output',
        stderrText: 'leaked error',
      );

      final result = agentActionExecutionToGetExecutionResult(
        execution,
        sanitizeForRemoteHub: true,
      );

      final process = result['process'] as Map<String, dynamic>;
      expect(process.containsKey('command_preview'), isFalse);

      final output = result['output'] as Map<String, dynamic>;
      final stdout = output['stdout'] as Map<String, dynamic>;
      final stderr = output['stderr'] as Map<String, dynamic>;
      expect(stdout['captured'], isFalse);
      expect(stderr['captured'], isFalse);
    });

    test('should omit failure block when execution has no failure metadata', () {
      final execution = AgentActionExecution(
        id: 'exec-ok-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime.utc(2026, 5, 18, 14),
        source: AgentActionRequestSource.remoteHub,
        finishedAt: DateTime.utc(2026, 5, 18, 14, 2),
        exitCode: 0,
        redactionApplied: true,
      );

      final result = agentActionExecutionToGetExecutionResult(execution);

      expect(result.containsKey('failure'), isFalse);
    });

    test('should serialize skipped execution with explicit skipped flag only', () {
      final execution = AgentActionExecution(
        id: 'exec-skipped-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.skipped,
        requestedAt: DateTime.utc(2026, 5, 20, 12),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime.utc(2026, 5, 20, 12, 0, 1),
        redactionApplied: true,
        failureCode: AgentActionFailureCode.queueIgnored,
        failurePhase: 'queue',
        failureMessage: 'Action execution was ignored because another execution is already running.',
      );

      final result = agentActionExecutionToGetExecutionResult(execution);

      expect(result['status'], 'skipped');
      final flags = result['flags'] as Map<String, dynamic>;
      expect(flags['terminal'], isTrue);
      expect(flags['skipped'], isTrue);
      expect(flags['cancelled'], isFalse);
      expect(flags['killed'], isFalse);
      expect(flags['timed_out'], isFalse);
    });
  });
}
