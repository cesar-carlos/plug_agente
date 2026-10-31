import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/actions/action_io_execution_projection.dart';
import 'package:plug_agente/application/actions/agent_action_execution_support_export.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/metrics/action_io_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_journal_retention.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  late ActionIoJournalDatabase db;
  late ActionIoOutputJournal output;
  late MetricsEventStore metrics;
  setUp(() async {
    db = ActionIoJournalDatabase(NativeDatabase.memory());
    metrics = MetricsEventStore(latencySampleCapacity: 16);
    output = ActionIoOutputJournal(
      db,
      ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1))),
      metrics: ActionIoMetricsCollector(metrics),
    );
    await db
        .into(db.actionIoSessions)
        .insert(
          ActionIoSessionsCompanion.insert(
            executionId: 'execution',
            installationId: 'installation',
            agentId: 'agent',
            clientId: 'client',
            actionId: 'action',
            idempotencyKey: 'key',
            fingerprint: 'fingerprint',
            triggerId: 'trigger',
            definitionHash: 'definition',
            processState: 'running',
            stdinState: 'open',
            captureState: 'capturing',
            createdAt: DateTime.now(),
          ),
        );
  });
  tearDown(() => db.close());

  test('an output commit wakes the reader with the durable event available', () async {
    final observer = output.observeChanges('execution');
    addTearDown(observer.close);
    final wake = observer.wait(const Duration(minutes: 1));
    (await output.append('execution', ActionIoStream.stderr, [0, 255])).getOrThrow();
    await wake.timeout(const Duration(seconds: 2));
    final page = (await output.read(
      executionId: 'execution',
      clientId: 'client',
      afterSequence: 0,
      maxBytes: ActionIoLimits.blockBytes,
    )).getOrThrow();
    expect((page.events.single as ActionIoOutputEvent).bytes, [0, 255]);
  });

  test('invalid integer bytes do not wrap into a valid journal record', () async {
    for (final bytes in [
      [-1],
      [256],
    ]) {
      expect((await output.append('execution', ActionIoStream.stdout, bytes)).isError(), isTrue);
    }
    final event = (await output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    expect(event.sequence, 1);
    expect(event.offset, 0);
    expect(event.bytes, [0, 255]);
  });

  test('support export from durable history excludes both original output streams', () async {
    const stdout = 'private-business-output-sentinel';
    const stderr = 'private-business-error-sentinel';
    await db.update(db.actionIoSessions).write(const ActionIoSessionsCompanion(actionType: Value('executable')));
    (await output.append('execution', ActionIoStream.stdout, utf8.encode(stdout))).getOrThrow();
    (await output.append('execution', ActionIoStream.stderr, utf8.encode(stderr))).getOrThrow();
    (await output.finish('execution', exitCode: 0, complete: true)).getOrThrow();
    final journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1))),
    );
    final snapshot = (await journal.getExecutionSnapshot('execution')).getOrThrow();
    final execution = ActionIoExecutionProjection.fromSnapshot(snapshot).getOrThrow();
    final exported = const AgentActionExecutionSupportExport().buildJson(execution);
    final metadata = jsonDecode(exported) as Map<String, dynamic>;
    expect(metadata['execution_id'], 'execution');
    expect(execution.stdoutText, isNull);
    expect(execution.stderrText, isNull);
    for (final payload in [stdout, stderr]) {
      expect(exported, isNot(contains(payload)));
      expect(exported, isNot(contains(base64Encode(utf8.encode(payload)))));
    }
    // Exporting diagnostics must not remove the separately authorized bytes.
    final retained = (await output.read(
      executionId: 'execution',
      clientId: 'client',
      afterSequence: 0,
      maxBytes: 65536,
    )).getOrThrow();
    final streams = retained.events.whereType<ActionIoOutputEvent>().toList();
    expect(streams.map((event) => event.stream), [ActionIoStream.stdout, ActionIoStream.stderr]);
    expect(streams.map((event) => utf8.decode(event.bytes)), [stdout, stderr]);
  });

  for (final (exitCode, complete, terminated, failureCode, counter) in [
    (0, true, true, null, MetricsCounterNames.actionIoExecutionSucceeded),
    (1, true, true, null, MetricsCounterNames.actionIoExecutionFailed),
    (0, false, true, 'ACTION_IO_STORAGE_FAILED', MetricsCounterNames.actionIoExecutionFailed),
    (0, true, true, 'ACTION_IO_UNAUTHORIZED', MetricsCounterNames.actionIoExecutionFailed),
    (null, false, false, 'ACTION_OUTCOME_UNKNOWN', MetricsCounterNames.actionIoExecutionUnknown),
    (null, true, true, 'ACTION_CANCELLED', MetricsCounterNames.actionIoExecutionCancelled),
  ]) {
    test('completion metrics distinguish $counter with capture complete=$complete', () async {
      (await output.finish(
        'execution',
        exitCode: exitCode,
        complete: complete,
        processTerminated: terminated,
        failureCode: failureCode,
      )).getOrThrow();
      expect(
        (await output.finish(
          'execution',
          exitCode: exitCode,
          complete: complete,
          processTerminated: terminated,
          failureCode: failureCode,
        )).isError(),
        isTrue,
      );
      expect(metrics.eventCounters, {
        counter: 1,
        (complete ? MetricsCounterNames.actionIoCaptureComplete : MetricsCounterNames.actionIoCaptureIncomplete): 1,
      });
    });
  }

  test('failed terminal commit publishes no execution or capture outcome', () async {
    await db.customStatement('''
      CREATE TEMP TRIGGER refuse_finish BEFORE UPDATE ON action_io_sessions
      WHEN NEW.process_state = 'finished'
      BEGIN SELECT RAISE(ABORT, 'fixture finish failure'); END
    ''');
    final result = await output.finish('execution', exitCode: 0, complete: true);
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
    expect(metrics.eventCounters, isEmpty);
    expect(await db.select(db.actionIoEvents).get(), isEmpty);
    expect((await db.select(db.actionIoSessions).getSingle()).processState, 'running');
  });
  Future<ActionIoReadPage> read([int after = 0]) async => (await output.read(
    executionId: 'execution',
    clientId: 'client',
    afterSequence: after,
    maxBytes: 65536,
  )).getOrThrow();

  test('crossing the shared byte limit commits exactly the permitted prefix', () async {
    await db
        .update(db.actionIoSessions)
        .write(const ActionIoSessionsCompanion(admittedInputBytes: Value(ActionIoLimits.executionBytes - 2)));
    final result = await output.append('execution', ActionIoStream.stderr, [0, 255, 65]);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_OUTPUT_LIMIT_EXCEEDED');
    expect((await output.append('execution', ActionIoStream.stdout, [65])).isError(), true);
    final page = await read();
    expect((page.events.single as ActionIoOutputEvent).bytes, [0, 255]);
    expect(page.nextSequence, 1);
  });

  test('SQLite page exhaustion rolls back output without losing its confirmed prefix', () async {
    (await output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    final pages = (await db.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
    await db.customStatement('PRAGMA max_page_count = $pages');
    final result = await output.append('execution', ActionIoStream.stdout, List<int>.filled(65536, 65));
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
    final prefix = await read();
    expect(prefix.events.whereType<ActionIoOutputEvent>().expand((event) => event.bytes), [0, 255]);
    expect(prefix.nextSequence, 1);
    final session = await db.select(db.actionIoSessions).getSingle();
    expect(session.stdoutBytes, 2);
    expect(session.nextEventSequence, 2);
    expect(await db.select(db.actionIoPayloads).get(), hasLength(1));
    expect(await db.select(db.actionIoEvents).get(), hasLength(1));
    expect(metrics.counterValue(MetricsCounterNames.actionIoPersistedOutputBytes), 2);
  });

  test('file-backed SQLite exhaustion preserves prefix and uncertainty across reopen', () async {
    final session = await db.select(db.actionIoSessions).getSingle();
    await db.close();
    final directory = await Directory.systemTemp.createTemp('action-io-full-reopen-');
    final file = File(p.join(directory.path, 'journal.sqlite'));
    var disk = ActionIoJournalDatabase(NativeDatabase(file));
    final cipher = ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1)));
    try {
      await disk.into(disk.actionIoSessions).insert(session.toCompanion(false));
      var diskOutput = ActionIoOutputJournal(disk, cipher);
      (await diskOutput.append('execution', ActionIoStream.stdout, [0, 255, 26])).getOrThrow();
      expect((await disk.customSelect('PRAGMA journal_mode').getSingle()).read<String>('journal_mode'), 'wal');
      expect((await disk.customSelect('PRAGMA synchronous').getSingle()).read<int>('synchronous'), 2);
      final pages = (await disk.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
      await disk.customStatement('PRAGMA max_page_count = $pages');
      final failure = await diskOutput.append('execution', ActionIoStream.stdout, List.filled(65536, 65));
      expect((failure.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
      await disk.close();
      disk = ActionIoJournalDatabase(NativeDatabase(file));
      final journal = DriftActionIoJournal(disk, cipher);
      expect((await journal.reconcileInterrupted()).getOrThrow(), 1);
      diskOutput = ActionIoOutputJournal(disk, cipher);
      final retained = (await diskOutput.read(
        executionId: 'execution',
        clientId: 'client',
        afterSequence: 0,
        maxBytes: 65536,
      )).getOrThrow();
      expect(retained.events.whereType<ActionIoOutputEvent>().expand((event) => event.bytes), [0, 255, 26]);
      expect(retained.outputComplete, isFalse);
      final snapshot = (await journal.getExecutionSnapshot('execution')).getOrThrow();
      expect(snapshot.processState, 'unknown');
      expect(snapshot.captureState, 'incomplete');
      expect((await journal.markStarting('execution')).isError(), isTrue);
      expect((await journal.beginNextInput('execution')).getOrThrow().input, isNull);
      expect(await disk.select(disk.actionIoPayloads).get(), hasLength(1));
      expect((await disk.select(disk.actionIoSessions).getSingle()).stdoutBytes, 3);
      expect((await disk.customSelect('PRAGMA integrity_check').getSingle()).read<String>('integrity_check'), 'ok');
    } finally {
      await disk.close();
      await directory.delete(recursive: true);
    }
  });

  test('persisted byte metric counts both streams but not reads or rejected appends', () async {
    (await output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    (await output.append('execution', ActionIoStream.stderr, [26])).getOrThrow();
    await read();
    await read();
    expect((await output.append('execution', ActionIoStream.stdout, [])).isError(), isTrue);
    expect((await output.append('missing', ActionIoStream.stdout, [65])).isError(), isTrue);
    expect(metrics.eventCounters, {MetricsCounterNames.actionIoPersistedOutputBytes: 3});
  });

  test('physical refusal preserves captured prefix and permits incomplete finalization', () async {
    var deny = false;
    final full = ActionRuntimeFailure.withContext(message: 'Storage full.', code: 'ACTION_IO_STORAGE_SPACE_EXHAUSTED');
    output = ActionIoOutputJournal(
      db,
      ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1))),
      physicalCapacity: (_) async => deny ? Failure(full) : const Success(unit),
    );
    (await output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    deny = true;
    expect((await output.append('execution', ActionIoStream.stdout, [65])).exceptionOrNull(), same(full));
    (await output.finish(
      'execution',
      exitCode: 0,
      complete: false,
      failureCode: 'ACTION_IO_STORAGE_SPACE_EXHAUSTED',
    )).getOrThrow();
    final page = await read();
    expect(page.events.whereType<ActionIoOutputEvent>().single.bytes, [0, 255]);
    expect(page.events.whereType<ActionIoCompletedEvent>().single.failureCode, 'ACTION_IO_STORAGE_SPACE_EXHAUSTED');
    expect(page.outputComplete, isFalse);
    expect(page.terminal, isTrue);
  });
  test('queued cancellation commits before spawn and preserves receipts without replay', () async {
    final input = DriftActionIoJournal(db, ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1))));
    await (db.update(db.actionIoSessions)..where((s) => s.executionId.equals('execution'))).write(
      const ActionIoSessionsCompanion(processState: Value('queued')),
    );
    (await input.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'message',
      sequence: 0,
      bytes: [0, 255],
    )).getOrThrow();
    expect((await output.cancelQueued('execution', 'other')).isError(), isTrue);
    expect((await input.getExecutionSnapshot('execution')).getOrThrow().processState, 'queued');
    expect((await output.cancelQueued('execution', 'client')).getOrThrow(), isTrue);
    expect((await input.markStarting('execution')).isError(), isTrue);
    final snapshot = (await input.getExecutionSnapshot('execution')).getOrThrow();
    expect(snapshot.processState, 'finished');
    expect(snapshot.failureCode, 'ACTION_CANCELLED');
    expect(snapshot.captureState, 'complete');
    expect(snapshot.terminalAt, isNotNull);
    final receipt = (await input.inputStatus('execution', 'client', 'message')).getOrThrow();
    expect(receipt.state, ActionIoDeliveryState.failed);
    expect(receipt.confirmedBytes, 0);
    final before = await db.select(db.actionIoEvents).get();
    expect((await output.cancelQueued('execution', 'client')).getOrThrow(), isFalse);
    expect(await db.select(db.actionIoEvents).get(), hasLength(before.length));
    expect(metrics.counterValue(MetricsCounterNames.actionIoExecutionCancelled), 1);
    expect(metrics.counterValue(MetricsCounterNames.actionIoCaptureComplete), 1);
  });

  test('starting wins the race without being falsely finalized by queued cancellation', () async {
    final input = DriftActionIoJournal(db, ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1))));
    await (db.update(db.actionIoSessions)..where((s) => s.executionId.equals('execution'))).write(
      const ActionIoSessionsCompanion(processState: Value('queued')),
    );
    final starting = input.markStarting('execution');
    final cancelling = output.cancelQueued('execution', 'client');
    (await starting).getOrThrow();
    expect((await cancelling).getOrThrow(), isFalse);
    expect((await input.getExecutionSnapshot('execution')).getOrThrow().processState, 'starting');
    expect(await db.select(db.actionIoEvents).get(), isEmpty);
  });

  test('complete capture preserves an independent execution failure without claiming success', () async {
    (await output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    final finished = await output.finish(
      'execution',
      exitCode: 0,
      complete: true,
      failureCode: 'ACTION_OUTCOME_UNKNOWN',
    );
    expect(finished.isSuccess(), isTrue);
    final page = await read();
    expect(page.outputComplete, isTrue);
    final completed = page.events.whereType<ActionIoCompletedEvent>().single;
    expect(completed.failureCode, 'ACTION_OUTCOME_UNKNOWN');
    final session = await db.select(db.actionIoSessions).getSingle();
    expect(session.captureState, 'complete');
    expect(session.failureCode, 'ACTION_OUTCOME_UNKNOWN');
  });

  test('pages contain whole encrypted blocks and independently ordered streams', () async {
    final large = List.filled(65536, 255);
    await output.append('execution', ActionIoStream.stdout, large);
    await output.append('execution', ActionIoStream.stderr, [0, 13, 10, 26]);
    await output.append('execution', ActionIoStream.stdout, [128]);
    final first = await read();
    expect(first.events, hasLength(1));
    expect((first.events.single as ActionIoOutputEvent).bytes, large);
    expect(first.nextSequence, 1);
    final second = await read(first.nextSequence);
    expect(second.events, hasLength(2));
    expect((second.events[0] as ActionIoOutputEvent).offset, 0);
    expect((second.events[1] as ActionIoOutputEvent).offset, 65536);
    expect(second.nextSequence, 3);
    expect((await read(3)).events, isEmpty);
  });

  test('exit zero does not hide incomplete capture and terminal events advance cursor', () async {
    await output.append('execution', ActionIoStream.stdout, [1]);
    expect(
      (await output.finish(
        'execution',
        exitCode: 0,
        complete: false,
        failureCode: 'ACTION_OUTPUT_LIMIT_EXCEEDED',
      )).isSuccess(),
      isTrue,
    );
    final page = await read();
    expect(page.terminal, isTrue);
    expect(page.outputComplete, isFalse);
    expect((page.events[1] as ActionIoProcessExitedEvent).exitCode, 0);
    expect((page.events[2] as ActionIoCompletedEvent).failureCode, 'ACTION_OUTPUT_LIMIT_EXCEEDED');
    expect(page.nextSequence, 3);
    expect((await output.append('execution', ActionIoStream.stdout, [2])).isError(), isTrue);
  });

  test('corrupt encrypted output never produces a successful partial page', () async {
    await output.append('execution', ActionIoStream.stdout, [1, 2]);
    await db
        .update(db.actionIoPayloads)
        .write(ActionIoPayloadsCompanion(ciphertext: Value(Uint8List.fromList([3, 4]))));
    expect(
      (await output.read(executionId: 'execution', clientId: 'client', afterSequence: 0, maxBytes: 65536)).isError(),
      isTrue,
    );
  });

  test('owner, cursor and page size are enforced', () async {
    for (final request in [
      (client: 'other', cursor: 0, size: 65536),
      (client: 'client', cursor: 1, size: 65536),
      (client: 'client', cursor: 0, size: 1),
    ]) {
      expect(
        (await output.read(
          executionId: 'execution',
          clientId: request.client,
          afterSequence: request.cursor,
          maxBytes: request.size,
        )).isError(),
        isTrue,
      );
    }
  });

  test('retention removes output at its deadline but preserves deduplication and nonce history', () async {
    await output.append('execution', ActionIoStream.stdout, [0, 255, 13, 10]);
    await output.finish('execution', exitCode: 0, complete: true);
    final session = await db.select(db.actionIoSessions).getSingle();
    final envelope = await db.select(db.actionIoPayloads).getSingle();
    final retention = ActionIoJournalRetention(db);
    expect((await retention.expire(session.outputExpiresAt!.subtract(const Duration(seconds: 1)))).getOrThrow(), 0);
    expect((await read()).events.first, isA<ActionIoOutputEvent>());
    expect((await retention.expire(session.outputExpiresAt!)).getOrThrow(), 1);
    final expired = await db.select(db.actionIoPayloads).getSingle();
    expect(expired.ciphertext, isEmpty);
    expect(expired.plaintextBytes, 0);
    expect(expired.nonce, envelope.nonce);
    expect(expired.keyId, envelope.keyId);
    final tombstone = await db.select(db.actionIoSessions).getSingle();
    expect(tombstone.idempotencyKey, session.idempotencyKey);
    expect(tombstone.fingerprint, session.fingerprint);
    expect(tombstone.stdoutBytes, 4);
    final response = await output.read(
      executionId: 'execution',
      clientId: 'client',
      afterSequence: 0,
      maxBytes: 65536,
    );
    expect((response.exceptionOrNull()! as ActionFailure).code, 'OUTPUT_EXPIRED');
    expect((await retention.expire(session.outputExpiresAt!)).getOrThrow(), 0);
  });

  test('retention cannot expire unknown outcomes even with stale expiration fields', () async {
    await output.append('execution', ActionIoStream.stderr, [26, 0]);
    await output.finish(
      'execution',
      exitCode: null,
      complete: false,
      processTerminated: false,
      failureCode: 'ACTION_OUTCOME_UNKNOWN',
    );
    final before = await db.select(db.actionIoSessions).getSingle();
    expect(before.terminalAt, isNull);
    expect(before.outputExpiresAt, isNull);
    final stale = DateTime.utc(2020);
    await db
        .update(db.actionIoSessions)
        .write(
          ActionIoSessionsCompanion(
            terminalAt: Value(stale),
            outputExpiresAt: Value(stale),
            dedupeExpiresAt: Value(stale),
          ),
        );
    expect((await ActionIoJournalRetention(db).expire(DateTime.utc(2026))).getOrThrow(), 0);
    expect((await db.select(db.actionIoPayloads).getSingle()).ciphertext, isNotEmpty);
    expect((await read()).events.first, isA<ActionIoOutputEvent>());
  });

  test('read refuses expired output before the maintenance sweep runs', () async {
    await output.append('execution', ActionIoStream.stdout, [1]);
    await output.finish('execution', exitCode: 0, complete: true);
    await db
        .update(db.actionIoSessions)
        .write(
          ActionIoSessionsCompanion(
            outputExpiresAt: Value(DateTime.now().subtract(const Duration(seconds: 1))),
          ),
        );
    final response = await output.read(
      executionId: 'execution',
      clientId: 'client',
      afterSequence: 0,
      maxBytes: 65536,
    );
    expect(response.exceptionOrNull(), isA<ActionFailure>());
    expect((response.exceptionOrNull()! as ActionFailure).code, 'OUTPUT_EXPIRED');
  });

  test('input and output share an atomic global content budget', () async {
    await output.append('execution', ActionIoStream.stdout, [1]);
    // Model existing retained content without allocating a GiB in the fixture.
    await db
        .update(db.actionIoPayloads)
        .write(
          const ActionIoPayloadsCompanion(plaintextBytes: Value(ActionIoLimits.payloadBytes - 1)),
        );
    final input = DriftActionIoJournal(db, ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1))));
    final results = await Future.wait([
      output.append('execution', ActionIoStream.stderr, [2]),
      input.admitInput(executionId: 'execution', clientId: 'client', messageId: 'm', sequence: 0, bytes: [3]),
    ]);
    expect(results.where((r) => r.isSuccess()), hasLength(1));
    expect(
      (results.singleWhere((r) => r.isError()).exceptionOrNull()! as ActionFailure).code,
      'ACTION_IO_STORAGE_QUOTA_EXCEEDED',
    );
    final session = await db.select(db.actionIoSessions).getSingle();
    expect(session.stdoutBytes + session.stderrBytes + session.admittedInputBytes, 2);
    expect(await db.select(db.actionIoPayloads).get(), hasLength(2));
  });

  test('negative retained payload accounting cannot hide behind a positive total', () async {
    (await output.append('execution', ActionIoStream.stdout, [1, 2, 3])).getOrThrow();
    (await output.append('execution', ActionIoStream.stderr, [4])).getOrThrow();
    final rows = await db.select(db.actionIoPayloads).get();
    await (db.update(db.actionIoPayloads)..where((row) => row.payloadId.equals(rows.last.payloadId))).write(
      const ActionIoPayloadsCompanion(plaintextBytes: Value(-1)),
    );
    final refused = await output.append('execution', ActionIoStream.stdout, [5]);
    expect(refused.isError(), isTrue);
    expect((refused.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_BUDGET_INVALID');
    expect(await db.select(db.actionIoPayloads).get(), hasLength(2));
    final session = await db.select(db.actionIoSessions).getSingle();
    expect(session.stdoutBytes, 3);
    expect(session.stderrBytes, 1);
  });
}
