import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_local_cancellation.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:result_dart/result_dart.dart';

class _Sessions extends Mock implements IActionIoSessionLookup {}

class _Output extends Mock implements IActionIoOutputJournal {}

ActionIoExecutionSnapshot _snapshot(String state) => ActionIoExecutionSnapshot(
  session: const ActionIoSessionReference(
    executionId: 'e',
    installationId: 'i',
    agentId: 'a',
    clientId: 'owner',
    actionId: 'action',
    actionType: 'executable',
  ),
  idempotencyKey: 'key',
  createdAt: DateTime.utc(2026),
  processState: state,
  stdinState: 'open',
  captureState: 'capturing',
  outputExpired: false,
);

void main() {
  test('running cancellation requests the owned process without claiming termination', () async {
    final sessions = _Sessions();
    final output = _Output();
    when(() => sessions.getExecutionSnapshot('e')).thenAnswer((_) async => Success(_snapshot('running')));
    when(() => output.cancelQueued('e', 'owner')).thenAnswer((_) async => const Success(false));
    var stops = 0;
    final cancel = ActionIoLocalCancellation(
      sessions: sessions,
      output: output,
      requestCancel: (id) {
        expect(id, 'e');
        stops++;
        return const Success(true);
      },
    );
    final result = await cancel(executionId: 'e', authorize: () async => const Success(unit));
    expect(result.getOrThrow().status, AgentActionExecutionStatus.running);
    expect(stops, 1);
    expect(result.getOrThrow().finishedAt, isNull);
  });

  test('revocation before native cancellation prevents a stop request', () async {
    final sessions = _Sessions();
    final output = _Output();
    when(() => sessions.getExecutionSnapshot('e')).thenAnswer((_) async => Success(_snapshot('running')));
    when(() => output.cancelQueued('e', 'owner')).thenAnswer((_) async => const Success(false));
    var checks = 0;
    final denied = ActionAuthorizationFailure('Local operation is unavailable.');
    final cancel = ActionIoLocalCancellation(
      sessions: sessions,
      output: output,
      requestCancel: (_) => throw StateError('Must not stop'),
    );
    final result = await cancel(
      executionId: 'e',
      authorize: () async => ++checks < 3 ? const Success(unit) : Failure(denied),
    );
    expect(result.exceptionOrNull(), same(denied));
  });

  test('unknown process never recreates handles or mutates queued state', () async {
    final sessions = _Sessions();
    final output = _Output();
    when(() => sessions.getExecutionSnapshot('e')).thenAnswer((_) async => Success(_snapshot('unknown')));
    final cancel = ActionIoLocalCancellation(
      sessions: sessions,
      output: output,
      requestCancel: (_) => throw StateError('Must not stop'),
    );
    final result = await cancel(executionId: 'e', authorize: () async => const Success(unit));
    expect(result.getOrThrow().status, AgentActionExecutionStatus.unknown);
    verifyZeroInteractions(output);
  });
}
