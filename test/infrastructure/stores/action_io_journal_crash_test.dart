@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:test/test.dart';

import '../../helpers/action_io_crash_child.dart';

void main() {
  // Flutter's resolved executable is flutter_tester, not the Dart CLI.
  final executable = File(Platform.resolvedExecutable);
  final dartExecutable = p.basenameWithoutExtension(executable.path) == 'flutter_tester'
      ? p.join(executable.parent.parent.parent.parent.path, 'dart-sdk', 'bin', Platform.isWindows ? 'dart.exe' : 'dart')
      : executable.path;
  const committedStages = ['claimed', 'admitted', 'starting', 'running', 'writing', 'written'];
  final stages = [...committedStages, for (final stage in committedStages) '$stage-uncommitted'];
  const outputCommits = ['stdout', 'stderr', 'completed'];
  final outputStages = [...outputCommits, for (final stage in outputCommits) '$stage-uncommitted'];
  final directories = <String, Directory>{};
  setUpAll(() async {
    expect(File(dartExecutable).existsSync(), isTrue, reason: 'Dart CLI required for isolated crash children');
    // Finish native-asset preparation in every child before this process loads
    // SQLite: Windows keeps a loaded DLL locked even after closing the database.
    for (final stage in [...stages, ...outputStages]) {
      final directory = await Directory.systemTemp.createTemp('action-io-crash-test-');
      directories[stage] = directory;
      final child = await Process.run(dartExecutable, [
        'run',
        'test/helpers/action_io_crash_child.dart',
        '${directory.path}/journal.sqlite',
        stage,
      ]);
      expect(child.exitCode, 77, reason: '${child.stdout}\n${child.stderr}');
    }
  });
  tearDownAll(() async {
    for (final directory in directories.values) {
      await directory.delete(recursive: true);
    }
  });
  for (final stage in outputStages) {
    test('interruption at $stage retains only committed output and completion', () async {
      final db = ActionIoJournalDatabase(NativeDatabase(File('${directories[stage]!.path}/journal.sqlite')));
      try {
        final journal = DriftActionIoJournal(db, crashCipher());
        final output = ActionIoOutputJournal(db, crashCipher());
        final committedIndex =
            outputCommits.indexOf(stage.replaceFirst('-uncommitted', '')) - (stage.endsWith('-uncommitted') ? 1 : 0);
        final completed = committedIndex == 2;
        final session = await db.select(db.actionIoSessions).getSingle();
        expect(session.stdoutBytes, committedIndex >= 0 ? 3 : 0);
        expect(session.stderrBytes, committedIndex >= 1 ? 3 : 0);
        expect(session.processState, completed ? 'finished' : 'running');
        expect(session.captureState, completed ? 'complete' : 'capturing');
        expect((await journal.reconcileInterrupted()).getOrThrow(), completed ? 0 : 1);
        expect((await journal.reconcileInterrupted()).getOrThrow(), 0);
        final page = (await output.read(
          executionId: 'execution',
          clientId: 'client',
          afterSequence: 0,
          maxBytes: 65536,
        )).getOrThrow();
        // A lost process is unknown, not a confirmed terminal execution.
        expect(page.terminal, completed);
        expect(page.outputComplete, completed);
        final recovered = await db.select(db.actionIoSessions).getSingle();
        expect(recovered.processState, completed ? 'finished' : 'unknown');
        expect(recovered.captureState, completed ? 'complete' : 'incomplete');
        final events = page.events.whereType<ActionIoOutputEvent>().toList();
        expect(events.map((event) => event.stream), [
          if (committedIndex >= 0) ActionIoStream.stdout,
          if (committedIndex >= 1) ActionIoStream.stderr,
        ]);
        expect(events.map((event) => event.bytes), [
          if (committedIndex >= 0) [0, 255, 26],
          if (committedIndex >= 1) [13, 10, 128],
        ]);
        expect(events.map((event) => event.offset), everyElement(0));
        expect(events.map((event) => event.sequence), List.generate(events.length, (index) => index + 1));
        expect((await journal.claim(crashIntent)).getOrThrow().created, isFalse);
        expect((await journal.markStarting('execution')).isError(), isTrue);
        expect((await journal.beginNextInput('execution')).getOrThrow().input, isNull);
        expect((await journal.inputStatus('execution', 'client', 'input')).getOrThrow().confirmedBytes, 5);
        expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');
      } finally {
        await db.close();
      }
    });
  }
  for (final stage in stages) {
    test('process interruption at $stage boundary preserves only committed state', () async {
      final directory = directories[stage]!;
      final file = File('${directory.path}/journal.sqlite');
      final db = ActionIoJournalDatabase(NativeDatabase(file));
      try {
        final journal = DriftActionIoJournal(db, crashCipher());
        expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');
        final uncommitted = stage.endsWith('-uncommitted');
        final baseStage = stage.replaceFirst('-uncommitted', '');
        final committedIndex = committedStages.indexOf(baseStage) - (uncommitted ? 1 : 0);
        if (committedIndex < 0) {
          expect(await db.select(db.actionIoSessions).get(), isEmpty);
          expect(await db.select(db.actionIoMessages).get(), isEmpty);
          expect(await db.select(db.actionIoPayloads).get(), isEmpty);
          expect((await journal.reconcileInterrupted()).getOrThrow(), 0);
          expect((await journal.claim(crashIntent)).getOrThrow().created, isTrue);
          return;
        }
        final durableStage = committedStages[committedIndex];
        final session = await db.select(db.actionIoSessions).getSingle();
        expect(session.admittedInputBytes, committedIndex >= 1 ? 5 : 0);
        expect(session.nextInputSequence, committedIndex >= 1 ? 1 : 0);
        expect(
          session.processState,
          committedIndex < 2
              ? 'queued'
              : committedIndex == 2
              ? 'starting'
              : 'running',
        );
        final messages = await db.select(db.actionIoMessages).get();
        final payloads = await db.select(db.actionIoPayloads).get();
        expect(messages.length, committedIndex >= 1 ? 1 : 0);
        expect(payloads.length, committedIndex >= 1 ? 1 : 0);
        expect(session.queuedInputBytes, committedIndex >= 1 && committedIndex < 5 ? 5 : 0);
        if (messages.isNotEmpty) {
          expect(
            messages.single.deliveryState,
            committedIndex == 5
                ? 'written'
                : committedIndex == 4
                ? 'writing'
                : 'accepted',
          );
        }
        expect((await journal.reconcileInterrupted()).getOrThrow(), 1);
        expect((await journal.reconcileInterrupted()).getOrThrow(), 0);
        expect((await journal.claim(crashIntent)).getOrThrow().created, isFalse);
        expect((await journal.markStarting('execution')).isError(), isTrue);
        expect((await journal.beginNextInput('execution')).getOrThrow().input, isNull);
        if (durableStage != 'claimed') {
          final receipt = (await journal.inputStatus('execution', 'client', 'input')).getOrThrow();
          expect(
            receipt.state,
            durableStage == 'written'
                ? ActionIoDeliveryState.written
                : durableStage == 'writing'
                ? ActionIoDeliveryState.unknown
                : ActionIoDeliveryState.failed,
          );
          expect(
            receipt.confirmedBytes,
            durableStage == 'written'
                ? 5
                : durableStage == 'writing'
                ? null
                : 0,
          );
        }
      } finally {
        await db.close();
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
