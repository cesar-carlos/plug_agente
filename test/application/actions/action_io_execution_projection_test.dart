import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_execution_projection.dart';
import 'package:plug_agente/application/rpc/agent_action_execution_rpc_mapper.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  ActionIoExecutionSnapshot snapshot({
    String process = 'finished',
    String capture = 'complete',
    int? exit = 0,
    String? failure,
    String? type = 'executable',
  }) => ActionIoExecutionSnapshot(
    session: ActionIoSessionReference(
      executionId: 'e',
      installationId: 'i',
      agentId: 'a',
      clientId: 'c',
      actionId: 'action',
      triggerId: 'trigger',
      definitionHash: 'hash',
      actionType: type,
    ),
    idempotencyKey: 'key',
    createdAt: DateTime.utc(2026),
    processState: process,
    stdinState: 'closed',
    captureState: capture,
    outputExpired: false,
    exitCode: exit,
    failureCode: failure,
  );
  test('projects durable outcome without claiming capture or unknown outcomes succeeded', () {
    for (final entry in [
      (snapshot(), AgentActionExecutionStatus.succeeded),
      (snapshot(exit: 7), AgentActionExecutionStatus.succeeded),
      (snapshot(exit: 7, failure: 'ACTION_EXIT_CODE_REJECTED'), AgentActionExecutionStatus.failed),
      (snapshot(capture: 'incomplete'), AgentActionExecutionStatus.failed),
      (snapshot(process: 'unknown'), AgentActionExecutionStatus.unknown),
      (snapshot(exit: null), AgentActionExecutionStatus.unknown),
      (snapshot(failure: 'ACTION_CANCELLED'), AgentActionExecutionStatus.cancelled),
      (snapshot(failure: 'ACTION_TIMEOUT'), AgentActionExecutionStatus.timedOut),
      (snapshot(process: 'queued', exit: null), AgentActionExecutionStatus.queued),
      (snapshot(process: 'starting', exit: null), AgentActionExecutionStatus.running),
    ]) {
      final execution = ActionIoExecutionProjection.fromSnapshot(entry.$1).getOrThrow();
      expect(execution.status, entry.$2);
      expect(execution.ioStatus?.processState, entry.$1.processState);
      expect(execution.ioStatus?.captureState, entry.$1.captureState);
      expect(execution.copyWith().ioStatus, same(execution.ioStatus));
      final wire = agentActionExecutionToGetExecutionResult(execution, sanitizeForRemoteHub: true);
      expect(wire['definition_snapshot_hash'], 'hash');
      expect(wire['idempotency_key'], 'key');
      final output = wire['output'] as Map<String, dynamic>;
      expect((output['stdout'] as Map<String, dynamic>)['captured'], isFalse);
      expect((output['stdout'] as Map<String, dynamic>).containsKey('text'), isFalse);
    }
  });
  test('missing original type and invalid states fail explicitly', () {
    for (final value in [snapshot(type: null), snapshot(process: 'invalid')]) {
      expect(
        (ActionIoExecutionProjection.fromSnapshot(value).exceptionOrNull()! as ActionRuntimeFailure).code,
        'ACTION_IO_SNAPSHOT_UNAVAILABLE',
      );
    }
  });
}
