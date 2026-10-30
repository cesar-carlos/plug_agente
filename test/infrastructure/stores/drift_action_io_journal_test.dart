import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_history.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_history_page.dart';
import 'package:plug_agente/infrastructure/metrics/action_io_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_counter_constants.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_event_store.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/agent_action_use_case_test_support.dart' show FakeAgentActionRepository;

void main() {
  late ActionIoJournalDatabase db;
  late DriftActionIoJournal journal;
  late MetricsEventStore metrics;
  ActionIoSessionIntent intent({String id = 'execution', String fingerprint = 'fingerprint', String key = 'key'}) =>
      ActionIoSessionIntent(
        executionId: id,
        installationId: 'installation',
        agentId: 'agent',
        clientId: 'client',
        actionId: 'action',
        idempotencyKey: key,
        fingerprint: fingerprint,
        triggerId: 'trigger',
        definitionHash: 'definition',
        actionType: 'executable',
      );
  setUp(() {
    db = ActionIoJournalDatabase(NativeDatabase.memory());
    metrics = MetricsEventStore(latencySampleCapacity: 16);
    journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))),
      metrics: ActionIoMetricsCollector(metrics),
    );
  });
  tearDown(() => db.close());

  for (final corruption in ['ciphertext', 'authenticated_context', 'input_bytes']) {
    test('corrupt persisted stdin $corruption refuses delivery and cannot replay after restart', () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp('action-io-input-corrupt-');
      final file = File(p.join(directory.path, 'journal.sqlite'));
      var disk = ActionIoJournalDatabase(NativeDatabase(file));
      final cipher = ActionIoPayloadCipher(keyId: 'private-fixture', key: SecretKey(List.filled(32, 7)));
      try {
        var persisted = DriftActionIoJournal(disk, cipher);
        (await persisted.claim(intent())).getOrThrow();
        (await persisted.markStarting('execution')).getOrThrow();
        (await persisted.markRunning('execution')).getOrThrow();
        (await persisted.admitInput(
          executionId: 'execution',
          clientId: 'client',
          messageId: 'input',
          sequence: 0,
          bytes: [0, 255, 26],
        )).getOrThrow();
        final original = await disk.select(disk.actionIoPayloads).getSingle();
        if (corruption == 'ciphertext') {
          final changed = Uint8List.fromList(original.ciphertext)..[0] ^= 255;
          await disk.customStatement('UPDATE action_io_payloads SET ciphertext = ?', [changed]);
        } else if (corruption == 'authenticated_context') {
          final changed = Uint8List.fromList(original.authenticatedContext)..[0] ^= 1;
          await disk.customStatement('UPDATE action_io_payloads SET authenticated_context = ?', [changed]);
        } else {
          await disk.customStatement('UPDATE action_io_messages SET input_bytes = 4');
        }
        final refused = await persisted.beginNextInput('execution');
        expect(refused.exceptionOrNull(), isA<ActionFailure>());
        expect((refused.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_INTEGRITY_FAILED');
        final receipt = (await persisted.inputStatus('execution', 'client', 'input')).getOrThrow();
        expect(receipt.state, ActionIoDeliveryState.accepted);
        expect(receipt.confirmedBytes, 0);
        await disk.close();
        disk = ActionIoJournalDatabase(NativeDatabase(file));
        persisted = DriftActionIoJournal(disk, cipher);
        expect((await persisted.reconcileInterrupted()).getOrThrow(), 1);
        expect(
          (await persisted.inputStatus('execution', 'client', 'input')).getOrThrow().state,
          ActionIoDeliveryState.failed,
        );
        expect((await persisted.beginNextInput('execution')).getOrThrow().input, isNull);
        expect((await persisted.claim(intent())).getOrThrow().created, isFalse);
        expect((await persisted.markStarting('execution')).isError(), isTrue);
        expect(await disk.select(disk.actionIoPayloads).get(), hasLength(1));
        expect((await disk.select(disk.actionIoSessions).getSingle()).admittedInputBytes, 3);
      } finally {
        await disk.close();
        await directory.delete(recursive: true);
      }
    });
  }

  for (final closeInput in [false, true]) {
    test('SQLite exhaustion rolls back initial run admission with closeInput=$closeInput', () async {
      final pages = (await db.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
      await db.customStatement('PRAGMA max_page_count = $pages');
      final result = await journal.claim(
        intent(),
        io: ActionIoConfiguration(closeInput: closeInput, initialInput: List.filled(65536, 255)),
      );
      expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
      expect(await db.select(db.actionIoSessions).get(), isEmpty);
      expect(await db.select(db.actionIoMessages).get(), isEmpty);
      expect(await db.select(db.actionIoPayloads).get(), isEmpty);
      expect(await db.select(db.actionIoEvents).get(), isEmpty);
      expect((await journal.ownsExecution('execution')).getOrThrow(), isFalse);
      expect((await journal.reconcileInterrupted()).getOrThrow(), 0);
      expect((await journal.markStarting('execution')).isError(), isTrue);
      expect(metrics.counterValue(MetricsCounterNames.actionIoAdmittedInputBytes), 0);
      expect((await db.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');
    });
  }

  test('failed persistent input admission retains earlier receipts and quotas after reopen', () async {
    await db.close();
    final directory = await Directory.systemTemp.createTemp('action-io-input-full-');
    final file = File(p.join(directory.path, 'journal.sqlite'));
    var disk = ActionIoJournalDatabase(NativeDatabase(file));
    final cipher = ActionIoPayloadCipher(keyId: 'private-fixture', key: SecretKey(List.filled(32, 7)));
    try {
      var persisted = DriftActionIoJournal(disk, cipher);
      (await persisted.claim(intent())).getOrThrow();
      (await persisted.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'retained',
        sequence: 0,
        bytes: [0, 255, 26],
      )).getOrThrow();
      expect((await disk.customSelect('PRAGMA journal_mode').getSingle()).data.values.single, 'wal');
      expect((await disk.customSelect('PRAGMA synchronous').getSingle()).data.values.single, 2);
      final pages = (await disk.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
      await disk.customStatement('PRAGMA max_page_count = $pages');
      final refused = await persisted.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'refused',
        sequence: 1,
        bytes: List.filled(65536, 65),
      );
      expect((refused.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
      await disk.close();
      disk = ActionIoJournalDatabase(NativeDatabase(file));
      persisted = DriftActionIoJournal(disk, cipher);
      final recovered = await disk.select(disk.actionIoSessions).getSingle();
      expect(recovered.nextInputSequence, 1);
      expect(recovered.admittedInputBytes, 3);
      expect(recovered.queuedInputBytes, 3);
      expect(recovered.queuedInputMessages, 1);
      expect((await disk.select(disk.actionIoMessages).get()).map((row) => row.messageId), ['retained']);
      expect(await disk.select(disk.actionIoPayloads).get(), hasLength(1));
      expect(
        (await persisted.inputStatus('execution', 'client', 'retained')).getOrThrow().state,
        ActionIoDeliveryState.accepted,
      );
      expect((await persisted.inputStatus('execution', 'client', 'refused')).isError(), isTrue);
      expect((await persisted.reconcileInterrupted()).getOrThrow(), 1);
      final receipt = (await persisted.inputStatus('execution', 'client', 'retained')).getOrThrow();
      expect(receipt.state, ActionIoDeliveryState.failed);
      expect(receipt.confirmedBytes, 0);
      expect((await persisted.claim(intent())).getOrThrow().created, isFalse);
      expect((await persisted.markStarting('execution')).isError(), isTrue);
      expect((await persisted.beginNextInput('execution')).getOrThrow().input, isNull);
      expect((await disk.customSelect('PRAGMA integrity_check').getSingle()).data.values.single, 'ok');
    } finally {
      await disk.close();
      await directory.delete(recursive: true);
    }
  });

  for (final (state, progress, counter) in [
    (ActionIoDeliveryState.written, 2, MetricsCounterNames.actionIoInputWritten),
    (ActionIoDeliveryState.failed, 1, MetricsCounterNames.actionIoInputFailed),
    (ActionIoDeliveryState.unknown, null, MetricsCounterNames.actionIoInputUnknown),
  ]) {
    test('committed $state delivery counts once and preserves progress uncertainty', () async {
      (await journal.claim(intent())).getOrThrow();
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'message',
        sequence: 0,
        bytes: [0, 255],
      )).getOrThrow();
      (await journal.markStarting('execution')).getOrThrow();
      (await journal.markRunning('execution')).getOrThrow();
      (await journal.beginNextInput('execution')).getOrThrow();
      for (var i = 0; i < 2; i++) {
        (await journal.finishInput('execution', 'message', state, confirmedBytes: progress)).getOrThrow();
      }
      expect(metrics.counterValue(counter), 1);
      expect(metrics.counterValue(MetricsCounterNames.actionIoInputConfirmedBytes), progress ?? 0);
      expect(metrics.counterValue(MetricsCounterNames.actionIoInputUnknownProgress), progress == null ? 1 : 0);
      expect((await journal.inputStatus('execution', 'client', 'message')).getOrThrow().confirmedBytes, progress);
    });
  }

  test('SQLite page exhaustion refuses input without advancing its durable sequence', () async {
    (await journal.claim(intent())).getOrThrow();
    final pages = (await db.customSelect('PRAGMA page_count').getSingle()).read<int>('page_count');
    await db.customStatement('PRAGMA max_page_count = $pages');
    final result = await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'full',
      sequence: 0,
      bytes: List<int>.filled(65536, 65),
    );
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
    final session = await db.select(db.actionIoSessions).getSingle();
    expect(session.nextInputSequence, 0);
    expect(session.admittedInputBytes, 0);
    expect(session.queuedInputMessages, 0);
    expect(await db.select(db.actionIoPayloads).get(), isEmpty);
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
    expect((await journal.claim(intent())).getOrThrow().created, isFalse);
    expect(metrics.counterValue(MetricsCounterNames.actionIoAdmittedInputBytes), 0);
  });

  test('input metrics count unique initial and interactive bytes, not concurrent duplicates', () async {
    final io = ActionIoConfiguration(closeInput: false, initialInput: [0, 255]);
    for (final result in await Future.wait([journal.claim(intent(), io: io), journal.claim(intent(), io: io)])) {
      result.getOrThrow();
    }
    Future<Result<ActionIoMessageReceipt>> send() =>
        journal.admitInput(executionId: 'execution', clientId: 'client', messageId: 'next', sequence: 1, bytes: [26]);
    for (final result in await Future.wait([send(), send()])) {
      result.getOrThrow();
    }
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'next',
        sequence: 1,
        bytes: [27],
      )).isError(),
      isTrue,
    );
    expect(metrics.eventCounters, {MetricsCounterNames.actionIoAdmittedInputBytes: 3});
  });

  test('failed automatic close rolls back initial input without publishing byte metrics', () async {
    var checks = 0;
    journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))),
      metrics: ActionIoMetricsCollector(metrics),
      physicalCapacity: (_) async => ++checks == 3
          ? Failure(
              ActionRuntimeFailure.withContext(message: 'Storage full.', code: 'ACTION_IO_STORAGE_SPACE_EXHAUSTED'),
            )
          : const Success(unit),
    );
    final result = await journal.claim(intent(), io: ActionIoConfiguration(closeInput: true, initialInput: [0, 255]));
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_SPACE_EXHAUSTED');
    expect(await db.select(db.actionIoSessions).get(), isEmpty);
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
    expect(metrics.eventCounters, isEmpty);
  });

  test('paged legacy history crosses timestamp ties and removes stale journal projections', () async {
    final legacyDb = AppDatabase(executor: NativeDatabase.memory());
    final repository = AgentActionRepository(legacyDb);
    try {
      (await journal.claim(intent(id: '000', key: 'owned'))).getOrThrow();
      for (var i = 0; i < 205; i++) {
        (await repository.saveExecution(
          AgentActionExecution(
            id: i.toString().padLeft(3, '0'),
            actionId: 'action',
            actionType: AgentActionType.executable,
            status: AgentActionExecutionStatus.succeeded,
            requestedAt: DateTime.utc(2025),
            source: AgentActionRequestSource.localUi,
          ),
        )).getOrThrow();
      }
      final first = (await repository.listExecutionPage(limit: 200)).getOrThrow();
      final second = (await repository.listExecutionPage(
        limit: 200,
        after: AgentActionHistoryCursor(first.last.requestedAt, first.last.id),
      )).getOrThrow();
      expect(first, hasLength(200));
      expect(second.map((e) => e.id), ['200', '201', '202', '203', '204']);
      expect((await repository.listExecutionPage(limit: 0)).isError(), isTrue);
      final result = (await ListAgentActionExecutions(repository, ioHistory: journal)(
        statuses: {AgentActionExecutionStatus.succeeded},
        limit: 201,
      )).getOrThrow();
      expect(result, hasLength(201));
      expect(result.first.id, '001');
      expect(result.last.id, '201');
      expect(result.any((e) => e.id == '000'), isFalse);
    } finally {
      await legacyDb.close();
    }
  });

  test('physical refusal rolls back initial admission and preserves duplicate receipts', () async {
    var checks = 0;
    var deny = false;
    final full = ActionRuntimeFailure.withContext(message: 'Storage full.', code: 'ACTION_IO_STORAGE_SPACE_EXHAUSTED');
    journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))),
      physicalCapacity: (_) async {
        checks++;
        return deny || checks == 2 ? Failure(full) : const Success(unit);
      },
    );
    final refused = await journal.claim(intent(), io: ActionIoConfiguration(closeInput: false, initialInput: [0, 255]));
    expect(refused.exceptionOrNull(), same(full));
    expect(await db.select(db.actionIoSessions).get(), isEmpty);
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
    expect(await db.select(db.actionIoPayloads).get(), isEmpty);
    (await journal.claim(intent())).getOrThrow();
    (await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'm',
      sequence: 0,
      bytes: [0, 255],
    )).getOrThrow();
    deny = true;
    final before = checks;
    expect((await journal.claim(intent())).getOrThrow().created, isFalse);
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'm',
        sequence: 0,
        bytes: [0, 255],
      )).isSuccess(),
      isTrue,
    );
    expect(checks, before);
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'next',
        sequence: 1,
        bytes: [65],
      )).exceptionOrNull(),
      same(full),
    );
    expect((await journal.getExecutionSnapshot('execution')).getOrThrow().nextInputSequence, 1);
    expect(await db.select(db.actionIoPayloads).get(), hasLength(1));
  });
  test('history merges journal states before filtering and limiting legacy projections', () async {
    (await journal.claim(intent())).getOrThrow();
    final repository = FakeAgentActionRepository();
    repository.executions['execution'] = AgentActionExecution(
      id: 'execution',
      actionId: 'action',
      actionType: AgentActionType.executable,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime.utc(2026),
      source: AgentActionRequestSource.remoteHub,
    );
    repository.executions['legacy'] = AgentActionExecution(
      id: 'legacy',
      actionId: 'action',
      actionType: AgentActionType.executable,
      status: AgentActionExecutionStatus.succeeded,
      requestedAt: DateTime.utc(2025),
      source: AgentActionRequestSource.localUi,
    );
    final list = ListAgentActionExecutions(repository, ioHistory: journal);
    final entries = (await list(actionId: 'action', limit: 1)).getOrThrow();
    expect(entries.single.id, 'execution');
    expect(entries.single.status, AgentActionExecutionStatus.queued);
    expect(entries.single.ioStatus?.processState, 'queued');
    expect((await list(statuses: {AgentActionExecutionStatus.succeeded}, limit: 1)).getOrThrow().single.id, 'legacy');
    final page = (await journal.listExecutionSnapshots(limit: 1)).getOrThrow();
    expect(
      (await journal.listExecutionSnapshots(
        limit: 1,
        after: ActionIoHistoryCursor(page.single.createdAt, page.single.session.executionId),
      )).getOrThrow(),
      isEmpty,
    );
  });

  test('local history reads bounded filtered metadata without admitting or replaying work', () async {
    final start = DateTime.utc(2026, 10);
    var now = start;
    journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))),
      now: () => now,
    );
    (await journal.claim(intent(id: 'older', key: 'older'))).getOrThrow();
    now = start.add(const Duration(seconds: 1));
    (await journal.claim(intent(id: 'newer', key: 'newer'))).getOrThrow();
    final latest = (await journal.listExecutionSnapshots(limit: 1)).getOrThrow();
    expect(latest.single.session.executionId, 'newer');
    expect(latest.single.processState, 'queued');
    expect((await journal.listExecutionSnapshots(actionId: 'missing', limit: 10)).getOrThrow(), isEmpty);
    expect(
      (await journal.listExecutionSnapshots(
        idempotencyKey: 'older',
        limit: 10,
      )).getOrThrow().single.session.executionId,
      'older',
    );
    expect((await journal.listExecutionSnapshots(requestedAfter: now, limit: 10)).getOrThrow(), hasLength(1));
    expect((await journal.listExecutionSnapshots(limit: 0)).isError(), isTrue);
    expect((await journal.listExecutionSnapshots(limit: 1001)).isError(), isTrue);
    expect(await db.select(db.actionIoSessions).get(), hasLength(2));
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
  });

  test('execution snapshots preserve incomplete capture and unknown process independently', () async {
    final output = ActionIoOutputJournal(db, ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))));
    (await journal.claim(intent())).getOrThrow();
    final queued = (await journal.getExecutionSnapshot('execution')).getOrThrow();
    expect(queued.session.actionType, 'executable');
    expect(queued.processState, 'queued');
    expect(queued.idempotencyKey, 'key');
    expect(queued.terminalAt, isNull);
    (await journal.markStarting('execution')).getOrThrow();
    (await output.finish(
      'execution',
      exitCode: 0,
      complete: false,
      failureCode: 'ACTION_IO_CAPTURE_FAILED',
    )).getOrThrow();
    final incomplete = (await journal.getExecutionSnapshot('execution')).getOrThrow();
    expect(incomplete.processState, 'finished');
    expect(incomplete.captureState, 'incomplete');
    expect(incomplete.exitCode, 0);
    expect(incomplete.failureCode, 'ACTION_IO_CAPTURE_FAILED');
    expect(incomplete.terminalAt, isNotNull);
    expect(incomplete.createdAt, queued.createdAt);
    (await journal.claim(intent(id: 'unknown', key: 'unknown'))).getOrThrow();
    (await journal.markStarting('unknown')).getOrThrow();
    (await journal.reconcileInterrupted()).getOrThrow();
    final unknown = (await journal.getExecutionSnapshot('unknown')).getOrThrow();
    expect(unknown.processState, 'unknown');
    expect(unknown.terminalAt, isNull);
    expect(unknown.exitCode, isNull);
    expect((await journal.getExecutionSnapshot('missing')).isError(), isTrue);
  });
  test('dry-run checks duplicate content without persisting or replaying intents', () async {
    final io = ActionIoConfiguration(closeInput: true, initialInput: [0, 255]);
    final absent = (await journal.previewClaim(intent(), io: io)).getOrThrow();
    expect(absent.session, isNull);
    expect(await db.select(db.actionIoSessions).get(), isEmpty);
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
    expect(await db.select(db.actionIoPayloads).get(), isEmpty);
    (await journal.claim(intent(), io: io)).getOrThrow();
    (await journal.reconcileInterrupted()).getOrThrow();
    final duplicate = (await journal.previewClaim(intent(id: 'other'), io: io)).getOrThrow();
    expect(duplicate.session?.executionId, 'execution');
    expect(
      (await journal.previewClaim(
        intent(),
        io: ActionIoConfiguration(closeInput: true, initialInput: [1]),
      )).isError(),
      isTrue,
    );
    expect(await db.select(db.actionIoSessions).get(), hasLength(1));
    expect(await db.select(db.actionIoMessages).get(), hasLength(2));
  });
  test('concurrent starts reserve at most four slots and unknown outcomes retain capacity', () async {
    journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))),
      concurrencyLimit: () => 64,
    );
    for (var i = 0; i < 5; i++) {
      (await journal.claim(intent(id: 'e$i', key: 'k$i'))).getOrThrow();
    }
    final starts = await Future.wait(List.generate(5, (i) => journal.markStarting('e$i')));
    expect(starts.where((r) => r.isSuccess()), hasLength(4));
    expect(starts.where((r) => r.isError()), hasLength(1));
    final rows = await db.select(db.actionIoSessions).get();
    expect(rows.where((r) => r.processState == 'starting'), hasLength(4));
    final queued = rows.singleWhere((r) => r.processState == 'queued');
    expect((await journal.claim(intent(id: 'duplicate', key: 'k0'))).getOrThrow().created, isFalse);
    (await journal.reconcileInterrupted()).getOrThrow();
    (await journal.claim(intent(id: 'new', key: 'new'))).getOrThrow();
    expect((await journal.markStarting('new')).isError(), isTrue);
    expect((await journal.markStarting(queued.executionId)).isError(), isTrue);
  });

  test('live stricter concurrency limit is enforced without blocking queued admission', () async {
    var limit = 1;
    journal = DriftActionIoJournal(
      db,
      ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))),
      concurrencyLimit: () => limit,
    );
    (await journal.claim(intent(id: 'one', key: 'one'))).getOrThrow();
    (await journal.claim(intent(id: 'two', key: 'two'))).getOrThrow();
    (await journal.markStarting('one')).getOrThrow();
    expect((await journal.markStarting('two')).isError(), isTrue);
    limit = 2;
    (await journal.markStarting('two')).getOrThrow();
    (await journal.markRunning('one')).getOrThrow();
    (await journal.markRunning('two')).getOrThrow();
    (await journal.claim(intent(id: 'three', key: 'three'))).getOrThrow();
    expect((await journal.markStarting('three')).isError(), isTrue);
    final output = ActionIoOutputJournal(db, ActionIoPayloadCipher(keyId: 'test', key: SecretKey(List.filled(32, 7))));
    (await output.finish('one', exitCode: 0, complete: true)).getOrThrow();
    (await journal.markStarting('three')).getOrThrow();
  });
  test('initial bytes and automatic close are admitted atomically with reserved receipts', () async {
    final io = ActionIoConfiguration(closeInput: true, initialInput: [0, 255, 13, 10]);
    final claimed = (await journal.claim(intent(), io: io)).getOrThrow();
    expect(claimed.created, isTrue);
    expect(claimed.initialMessageId, ActionIoLimits.initialMessageId);
    expect(claimed.closeMessageId, ActionIoLimits.closeMessageId);
    final initial = (await journal.inputStatus('execution', 'client', claimed.initialMessageId!)).getOrThrow();
    final closed = (await journal.inputStatus('execution', 'client', claimed.closeMessageId!)).getOrThrow();
    expect(initial.sequence, 0);
    expect(initial.state, ActionIoDeliveryState.accepted);
    expect(initial.nextInputSequence, 2);
    expect(closed.sequence, 1);
    expect(closed.stdinState, ActionIoStdinState.closing);
    final duplicate = (await journal.claim(intent(id: 'duplicate'), io: io)).getOrThrow();
    expect(duplicate.created, isFalse);
    expect(duplicate.executionId, claimed.executionId);
    expect(await db.select(db.actionIoMessages).get(), hasLength(2));
    expect(
      (await journal.claim(intent(), io: ActionIoConfiguration(closeInput: true, initialInput: [1]))).isError(),
      isTrue,
    );
    (await journal.reconcileInterrupted()).getOrThrow();
    expect((await journal.claim(intent(), io: io)).getOrThrow().created, isFalse);
    expect(
      (await journal.inputStatus('execution', 'client', claimed.initialMessageId!)).getOrThrow().state,
      ActionIoDeliveryState.failed,
    );
  });

  test('failure inserting automatic close rolls back session initial payload and all reservations', () async {
    await db.customStatement('''
      CREATE TRIGGER reject_automatic_close BEFORE INSERT ON action_io_messages
      WHEN NEW.closes_input = 1 BEGIN SELECT RAISE(ABORT, 'fixture close failure'); END
    ''');
    final io = ActionIoConfiguration(closeInput: true, initialInput: [0, 255]);
    expect((await journal.claim(intent(), io: io)).isError(), isTrue);
    expect(await db.select(db.actionIoSessions).get(), isEmpty);
    expect(await db.select(db.actionIoMessages).get(), isEmpty);
    expect(await db.select(db.actionIoPayloads).get(), isEmpty);
    await db.customStatement('DROP TRIGGER reject_automatic_close');
    expect((await journal.claim(intent(), io: io)).getOrThrow().created, isTrue);
  });

  test('absent and empty initial input have different intent and sequence semantics', () async {
    final empty = ActionIoConfiguration(closeInput: false, initialInput: []);
    final claimed = (await journal.claim(intent(), io: empty)).getOrThrow();
    expect(claimed.initialMessageId, isNotNull);
    expect(claimed.closeMessageId, isNull);
    final receipt = (await journal.inputStatus('execution', 'client', claimed.initialMessageId!)).getOrThrow();
    expect(receipt.nextInputSequence, 1);
    expect(receipt.stdinState, ActionIoStdinState.pending);
    expect((await journal.claim(intent(), io: ActionIoConfiguration(closeInput: false))).isError(), isTrue);
  });

  test('automatic close without initial bytes occupies sequence zero', () async {
    final claim = (await journal.claim(intent(), io: ActionIoConfiguration(closeInput: true))).getOrThrow();
    expect(claim.initialMessageId, isNull);
    final close = (await journal.inputStatus('execution', 'client', claim.closeMessageId!)).getOrThrow();
    expect(close.sequence, 0);
    expect(close.nextInputSequence, 1);
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'late',
        sequence: 1,
        bytes: [],
      )).isError(),
      isTrue,
    );
  });

  test('execution lookup is scoped by installation agent client action and original key', () async {
    (await journal.claim(intent())).getOrThrow();
    final owner = (await journal.getSessionReference('execution')).getOrThrow();
    expect(owner.clientId, 'client');
    expect(owner.actionId, 'action');
    for (var changed = -1; changed < 5; changed++) {
      final parts = ['installation', 'agent', 'client', 'action', 'key'];
      if (changed >= 0) parts[changed] = 'other';
      final result = (await journal.findExecution(
        installationId: parts[0],
        agentId: parts[1],
        clientId: parts[2],
        actionId: parts[3],
        idempotencyKey: parts[4],
      )).getOrThrow();
      expect(result.session?.executionId, changed < 0 ? 'execution' : null);
    }
    (await journal.reconcileInterrupted()).getOrThrow();
    final retained = (await journal.findExecution(
      installationId: 'installation',
      agentId: 'agent',
      clientId: 'client',
      actionId: 'action',
      idempotencyKey: 'key',
    )).getOrThrow();
    expect(retained.session!.executionId, 'execution');
  });
  test('concurrent duplicate claims authorize exactly one new session', () async {
    final claims = await Future.wait([journal.claim(intent()), journal.claim(intent(id: 'second'))]);
    expect(claims.where((r) => r.getOrThrow().created), hasLength(1));
    expect(claims.map((r) => r.getOrThrow().executionId).toSet(), hasLength(1));
    expect((await journal.claim(intent(fingerprint: 'different'))).isError(), isTrue);
  });
  test('admission atomically stores ciphertext, receipt and quota; duplicates do not add bytes', () async {
    await journal.claim(intent());
    final first = await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'message',
      sequence: 0,
      bytes: [0, 255, 13, 10],
    );
    expect(first.getOrThrow().state, ActionIoDeliveryState.accepted);
    final duplicate = await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'message',
      sequence: 0,
      bytes: [0, 255, 13, 10],
    );
    expect(duplicate.isSuccess(), isTrue);
    final session = await db.select(db.actionIoSessions).getSingle();
    expect(session.admittedInputBytes, 4);
    expect(session.nextInputSequence, 1);
    final payload = await db.select(db.actionIoPayloads).getSingle();
    expect(payload.ciphertext, isNot([0, 255, 13, 10]));
    expect(payload.authenticationTag, hasLength(16));
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'message',
        sequence: 0,
        bytes: [1],
      )).isError(),
      isTrue,
    );
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'other',
        messageId: 'message',
        sequence: 0,
        bytes: [0, 255, 13, 10],
      )).isError(),
      isTrue,
    );
  });
  test('empty input consumes a sequence without closing; close admission excludes later writes', () async {
    await journal.claim(intent());
    final empty = await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'empty',
      sequence: 0,
      bytes: [],
    );
    expect(empty.getOrThrow().stdinState, ActionIoStdinState.pending);
    final close = await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'close',
      sequence: 1,
      bytes: [],
      close: true,
    );
    expect(close.getOrThrow().stdinState, ActionIoStdinState.closing);
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'late',
        sequence: 2,
        bytes: [1],
      )).isError(),
      isTrue,
    );
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'close',
        sequence: 1,
        bytes: [],
        close: true,
      )).isSuccess(),
      isTrue,
    );
  });
  test('queue capacity and reserved ids are rejected without persisting new payloads', () async {
    await journal.claim(intent());
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'system:initial',
        sequence: 0,
        bytes: [],
      )).isError(),
      isTrue,
    );
    for (var sequence = 0; sequence < 16; sequence++) {
      expect(
        (await journal.admitInput(
          executionId: 'execution',
          clientId: 'client',
          messageId: 'm$sequence',
          sequence: sequence,
          bytes: [],
        )).isSuccess(),
        isTrue,
      );
    }
    expect(
      (await journal.admitInput(
        executionId: 'execution',
        clientId: 'client',
        messageId: 'overflow',
        sequence: 16,
        bytes: [],
      )).isError(),
      isTrue,
    );
    expect(await db.select(db.actionIoPayloads).get(), hasLength(16));
  });
  test('only one worker can claim the next input and receipt becomes durable before delivery', () async {
    await journal.claim(intent());
    await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'first',
      sequence: 0,
      bytes: [0, 255],
    );
    await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'close',
      sequence: 1,
      bytes: [],
      close: true,
    );
    expect((await journal.beginNextInput('execution')).getOrThrow().input, isNull);
    expect((await journal.markStarting('execution')).isSuccess(), isTrue);
    expect((await journal.markRunning('execution')).isSuccess(), isTrue);
    final polls = await Future.wait([journal.beginNextInput('execution'), journal.beginNextInput('execution')]);
    final claimed = polls.map((r) => r.getOrThrow().input).whereType<ActionIoPendingInput>().single;
    expect(claimed.bytes, [0, 255]);
    expect(
      (await journal.inputStatus('execution', 'client', 'first')).getOrThrow().state,
      ActionIoDeliveryState.writing,
    );
    expect((await journal.beginNextInput('execution')).getOrThrow().input, isNull);
    expect(
      (await journal.finishInput('execution', 'first', ActionIoDeliveryState.written, confirmedBytes: 1)).isError(),
      isTrue,
    );
    expect(
      (await journal.finishInput('execution', 'first', ActionIoDeliveryState.written, confirmedBytes: 2)).isSuccess(),
      isTrue,
    );
    expect((await journal.beginNextInput('execution')).getOrThrow().input!.close, isTrue);
    final closed = await journal.finishInput('execution', 'close', ActionIoDeliveryState.written, confirmedBytes: 0);
    expect(closed.getOrThrow().stdinState, ActionIoStdinState.closed);
    final state = await db.select(db.actionIoSessions).getSingle();
    expect(state.queuedInputMessages, 0);
    expect(state.queuedInputBytes, 0);
    expect(state.admittedInputBytes, 2);
  });

  test('restart separates uncertain writes from untouched inputs without replaying either', () async {
    await journal.claim(intent());
    await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'started',
      sequence: 0,
      bytes: [1],
    );
    await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'queued',
      sequence: 1,
      bytes: [2],
    );
    await journal.markStarting('execution');
    await journal.markRunning('execution');
    await journal.beginNextInput('execution');
    expect((await journal.reconcileInterrupted()).getOrThrow(), 1);
    expect((await journal.reconcileInterrupted()).getOrThrow(), 0);
    expect(metrics.counterValue(MetricsCounterNames.actionIoInterruptedExecutions), 1);
    final started = (await journal.inputStatus('execution', 'client', 'started')).getOrThrow();
    final queued = (await journal.inputStatus('execution', 'client', 'queued')).getOrThrow();
    expect(started.state, ActionIoDeliveryState.unknown);
    expect(started.confirmedBytes, isNull);
    expect(queued.state, ActionIoDeliveryState.failed);
    expect(queued.confirmedBytes, 0);
    expect((await journal.beginNextInput('execution')).getOrThrow().input, isNull);
    expect((await journal.claim(intent())).getOrThrow().created, isFalse);
    expect((await journal.markStarting('execution')).isError(), isTrue);
    expect(
      (await journal.finishInput('execution', 'started', ActionIoDeliveryState.written, confirmedBytes: 1)).isError(),
      isTrue,
    );
    expect((await journal.inputStatus('execution', 'another-client', 'started')).isError(), isTrue);
    final state = await db.select(db.actionIoSessions).getSingle();
    expect(state.terminalAt, isNull);
    expect(state.outputExpiresAt, isNull);
    expect(state.admittedInputBytes, 2);
  });

  test('recovery rollback publishes no interrupted execution metric', () async {
    (await journal.claim(intent())).getOrThrow();
    (await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'started',
      sequence: 0,
      bytes: [255],
    )).getOrThrow();
    (await journal.markStarting('execution')).getOrThrow();
    (await journal.markRunning('execution')).getOrThrow();
    (await journal.beginNextInput('execution')).getOrThrow();
    await db.customStatement('''
      CREATE TEMP TRIGGER refuse_recovery BEFORE UPDATE ON action_io_sessions
      WHEN NEW.process_state = 'unknown'
      BEGIN SELECT RAISE(ABORT, 'fixture recovery failure'); END
    ''');
    final refused = await journal.reconcileInterrupted();
    expect(refused.isError(), isTrue);
    expect((refused.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
    expect(metrics.counterValue(MetricsCounterNames.actionIoInterruptedExecutions), 0);
    expect(
      (await journal.inputStatus('execution', 'client', 'started')).getOrThrow().state,
      ActionIoDeliveryState.writing,
    );
    expect((await journal.getExecutionSnapshot('execution')).getOrThrow().processState, 'running');
    await db.customStatement('DROP TRIGGER refuse_recovery');
    expect((await journal.reconcileInterrupted()).getOrThrow(), 1);
    expect(metrics.counterValue(MetricsCounterNames.actionIoInterruptedExecutions), 1);
  });

  test('delivery finalization rollback does not publish progress or outcome', () async {
    (await journal.claim(intent())).getOrThrow();
    (await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'message',
      sequence: 0,
      bytes: [255],
    )).getOrThrow();
    (await journal.markStarting('execution')).getOrThrow();
    (await journal.markRunning('execution')).getOrThrow();
    (await journal.beginNextInput('execution')).getOrThrow();
    await db.customStatement('''
      CREATE TEMP TRIGGER refuse_finish BEFORE UPDATE ON action_io_sessions
      WHEN NEW.queued_input_messages = 0
      BEGIN SELECT RAISE(ABORT, 'fixture finish failure'); END
    ''');
    final result = await journal.finishInput('execution', 'message', ActionIoDeliveryState.written, confirmedBytes: 1);
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
    expect(metrics.counterValue(MetricsCounterNames.actionIoInputWritten), 0);
    expect(metrics.counterValue(MetricsCounterNames.actionIoInputConfirmedBytes), 0);
    expect(
      (await journal.inputStatus('execution', 'client', 'message')).getOrThrow().state,
      ActionIoDeliveryState.writing,
    );
    expect((await db.select(db.actionIoSessions).getSingle()).queuedInputMessages, 1);
  });
}
