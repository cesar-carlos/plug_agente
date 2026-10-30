import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/action_io_running_session.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:result_dart/result_dart.dart';

class _Process extends Mock implements IActionIoProcess {}

class _Pipe extends Mock implements IActionIoInputPipe {}

class _InputJournal extends Mock implements IActionIoJournal {}

class _OutputJournal extends Mock implements IActionIoOutputJournal {}

void main() {
  for (final throwsOnClose in [false, true]) {
    test('authorization failure survives termination, close and commit failures (throws=$throwsOnClose)', () async {
      final process = _Process();
      final pipe = _Pipe();
      final input = _InputJournal();
      final output = _OutputJournal();
      final closingStarted = Completer<void>();
      final releaseClose = Completer<void>();
      final denied = ActionAuthorizationFailure.withContext(message: 'Revoked.', code: 'ACTION_IO_UNAUTHORIZED');
      final termination = ActionRuntimeFailure.withContext(
        message: 'Termination uncertain.',
        code: 'ACTION_OUTCOME_UNKNOWN',
      );
      final closing = ActionRuntimeFailure.withContext(message: 'Cleanup uncertain.', code: 'ACTION_IO_CLEANUP_FAILED');
      final storage = ActionRuntimeFailure.withContext(message: 'Commit failed.', code: 'ACTION_IO_STORAGE_FAILED');
      when(() => process.input).thenReturn(pipe);
      when(() => process.stdout).thenAnswer((_) => const Stream<List<int>>.empty());
      when(() => process.stderr).thenAnswer((_) => const Stream<List<int>>.empty());
      when(() => process.exitCode).thenAnswer((_) async => const Success(0));
      when(process.terminate).thenAnswer((_) async => Failure(termination));
      when(process.close).thenAnswer((_) async {
        closingStarted.complete();
        await releaseClose.future;
        if (throwsOnClose) throw StateError('private native diagnostic');
        return Failure(closing);
      });
      when(
        () => output.finish(
          'execution',
          exitCode: 0,
          complete: false,
          processTerminated: false,
          failureCode: 'ACTION_IO_UNAUTHORIZED',
        ),
      ).thenAnswer((_) async => Failure(storage));
      final session = ActionIoRunningSession(
        executionId: 'execution',
        process: process,
        inputJournal: input,
        outputJournal: output,
        authorize: () async => Failure(denied),
        deadline: DateTime.now().add(const Duration(seconds: 30)),
      );

      var completed = false;
      final running = session.run().then((result) {
        completed = true;
        return result;
      });
      await closingStarted.future;
      expect(completed, isFalse);
      verifyZeroInteractions(output);
      releaseClose.complete();
      expect((await running).exceptionOrNull(), same(denied));
      expect(session.secondaryFailures.map((failure) => failure.code), [
        'ACTION_OUTCOME_UNKNOWN',
        if (throwsOnClose) 'ACTION_OUTCOME_UNKNOWN' else 'ACTION_IO_CLEANUP_FAILED',
        'ACTION_IO_STORAGE_FAILED',
      ]);
      expect(
        session.secondaryFailures.map((failure) => failure.message).join(),
        isNot(contains('private native diagnostic')),
      );
      expect((await session.runAndDrain()).isError(), isTrue);
      expect((await session.stopAndDrain()).isError(), isTrue);
      expect((await session.run()).exceptionOrNull(), same(denied));
      verify(process.terminate).called(1);
      verify(process.close).called(1);
      verifyNever(process.resume);
      verifyZeroInteractions(input);
      verifyZeroInteractions(pipe);
      verify(
        () => output.finish(
          'execution',
          exitCode: 0,
          complete: false,
          processTerminated: false,
          failureCode: 'ACTION_IO_UNAUTHORIZED',
        ),
      ).called(1);
    });
  }
}
