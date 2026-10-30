import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_output_capture.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:result_dart/result_dart.dart';

class _Journal extends Mock implements IActionIoOutputJournal {}

void main() {
  test('draining alone does not finalize and complete output preserves input failure', () async {
    final journal = _Journal();
    final inputFailure = ActionRuntimeFailure.withContext(message: 'Input uncertain.', code: 'ACTION_OUTCOME_UNKNOWN');
    when(
      () => journal.finish('execution', exitCode: 0, complete: true, failureCode: 'ACTION_OUTCOME_UNKNOWN'),
    ).thenAnswer((_) async => const Success(unit));
    final capture = ActionIoOutputCapture(
      executionId: 'execution',
      journal: journal,
      stdout: const Stream.empty(),
      stderr: const Stream.empty(),
      terminate: () async => const Success(unit),
    );
    (await capture.drainAfterExit()).getOrThrow();
    verifyZeroInteractions(journal);
    expect((await capture.finishAfterExit(0, executionFailure: inputFailure)).exceptionOrNull(), same(inputFailure));
    verify(
      () => journal.finish('execution', exitCode: 0, complete: true, failureCode: 'ACTION_OUTCOME_UNKNOWN'),
    ).called(1);
  });
  test('zero exit with stalled output records incomplete capture and retains cleanup ownership', () {
    fakeAsync((clock) {
      final journal = _Journal();
      final output = StreamController<List<int>>();
      final termination = Completer<Result<Unit>>();
      var terminations = 0;
      when(
        () => journal.finish(
          'execution',
          exitCode: 0,
          complete: false,
          failureCode: 'ACTION_IO_DRAIN_TIMEOUT',
        ),
      ).thenAnswer((_) async => const Success(unit));
      final capture = ActionIoOutputCapture(
        executionId: 'execution',
        journal: journal,
        stdout: output.stream,
        stderr: const Stream.empty(),
        terminate: () {
          terminations++;
          return termination.future;
        },
      );
      Result<Unit>? result;
      var cleaned = false;
      capture.finishAfterExit(0).then((value) => result = value);
      capture.waitForCleanup().then((_) => cleaned = true);
      clock.elapse(const Duration(seconds: 4));
      expect(result, isNull);
      expect(terminations, 0);
      clock.elapse(const Duration(seconds: 1));
      expect((result!.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_DRAIN_TIMEOUT');
      expect(terminations, 1);
      expect(cleaned, isFalse);
      termination.complete(const Success(unit));
      unawaited(output.close());
      clock.flushMicrotasks();
      expect(cleaned, isTrue);
      verify(
        () => journal.finish(
          'execution',
          exitCode: 0,
          complete: false,
          failureCode: 'ACTION_IO_DRAIN_TIMEOUT',
        ),
      ).called(1);
    });
  });

  test('terminal capture commit is idempotent and storage failure is explicit', () async {
    final journal = _Journal();
    final storage = ActionRuntimeFailure.withContext(message: 'Storage failed.', code: 'ACTION_IO_STORAGE_FAILED');
    when(
      () => journal.finish('execution', exitCode: 0, complete: true),
    ).thenAnswer((_) async => Failure(storage));
    final capture = ActionIoOutputCapture(
      executionId: 'execution',
      journal: journal,
      stdout: const Stream.empty(),
      stderr: const Stream.empty(),
      terminate: () async => const Success(unit),
    );
    expect((await capture.finishAfterExit(0)).exceptionOrNull(), same(storage));
    expect((await capture.finishAfterExit(0)).exceptionOrNull(), same(storage));
    verify(() => journal.finish('execution', exitCode: 0, complete: true)).called(1);
  });

  test('does not request the next source block until the preceding commit completes', () async {
    final journal = _Journal();
    final commit = Completer<Result<ActionIoOutputEvent>>();
    var appends = 0;
    when(() => journal.append('execution', ActionIoStream.stdout, any())).thenAnswer((invocation) async {
      appends++;
      if (appends == 1) return commit.future;
      return Success(ActionIoOutputEvent(sequence: 2, stream: ActionIoStream.stdout, offset: 1, bytes: [2]));
    });
    final capture = ActionIoOutputCapture(
      executionId: 'execution',
      journal: journal,
      stdout: Stream.fromIterable([
        [1],
        [2],
      ]),
      stderr: const Stream.empty(),
      terminate: () async => const Success(unit),
    );
    await Future<void>.delayed(Duration.zero);
    expect(appends, 1);
    commit.complete(Success(ActionIoOutputEvent(sequence: 1, stream: ActionIoStream.stdout, offset: 0, bytes: [1])));
    expect((await capture.done).isSuccess(), isTrue);
    expect(appends, 2);
  });

  test('preserves storage failure as primary when termination also fails', () async {
    final journal = _Journal();
    final storage = ActionRuntimeFailure.withContext(message: 'Storage failed.', code: 'ACTION_IO_STORAGE_FAILED');
    final cleanup = ActionRuntimeFailure.withContext(message: 'Termination failed.', code: 'ACTION_IO_CLEANUP_FAILED');
    when(() => journal.append('execution', ActionIoStream.stdout, any())).thenAnswer((_) async => Failure(storage));
    var terminations = 0;
    final capture = ActionIoOutputCapture(
      executionId: 'execution',
      journal: journal,
      stdout: Stream.fromIterable([
        [1],
        [2],
      ]),
      stderr: const Stream.empty(),
      terminate: () async {
        terminations++;
        return Failure(cleanup);
      },
    );
    expect((await capture.done).exceptionOrNull(), same(storage));
    expect(capture.secondaryFailures, [cleanup]);
    expect(terminations, 1);
    verify(() => journal.append('execution', ActionIoStream.stdout, any())).called(1);
  });
}
