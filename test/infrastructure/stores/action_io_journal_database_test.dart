import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ActionIoSessionsCompanion session(String id, {String client = 'client'}) => ActionIoSessionsCompanion.insert(
    executionId: id,
    installationId: 'installation',
    agentId: 'agent',
    clientId: client,
    actionId: 'action',
    idempotencyKey: 'key',
    fingerprint: 'fingerprint',
    triggerId: 'trigger',
    definitionHash: 'definition',
    processState: 'queued',
    stdinState: 'pending',
    captureState: 'capturing',
    createdAt: DateTime.utc(2026, 10, 28),
  );

  test('persistent journal uses FULL/WAL and retains admitted identity after reopen', () async {
    final directory = await Directory.systemTemp.createTemp('action-io-journal-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.sqlite');
    var db = ActionIoJournalDatabase(NativeDatabase(file));
    await db.into(db.actionIoSessions).insert(session('execution'));
    expect((await db.customSelect('PRAGMA synchronous').getSingle()).data.values.single, 2);
    expect((await db.customSelect('PRAGMA journal_mode').getSingle()).data.values.single, 'wal');
    expect((await db.customSelect('PRAGMA foreign_keys').getSingle()).data.values.single, 1);
    await db.close();
    db = ActionIoJournalDatabase(NativeDatabase(file));
    addTearDown(db.close);
    expect((await db.select(db.actionIoSessions).getSingle()).executionId, 'execution');
    await expectLater(db.into(db.actionIoSessions).insert(session('duplicate')), throwsA(isA<Exception>()));
    await db.into(db.actionIoSessions).insert(session('other-owner', client: 'other'));
    expect(await db.select(db.actionIoSessions).get(), hasLength(2));
  });

  test('version one sessions migrate without inventing original action type', () async {
    final directory = await Directory.systemTemp.createTemp('action-io-migration-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.sqlite');
    var db = ActionIoJournalDatabase(NativeDatabase(file));
    await db.into(db.actionIoSessions).insert(session('old'));
    await db.customStatement('ALTER TABLE action_io_sessions DROP COLUMN action_type');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
    db = ActionIoJournalDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await db.customSelect('SELECT execution_id, action_type FROM action_io_sessions').getSingle();
    expect(row.data['execution_id'], 'old');
    expect(row.data['action_type'], isNull);
    expect((await db.customSelect('PRAGMA user_version').getSingle()).data.values.single, 2);
  });

  test('transaction failure leaves no admitted session', () async {
    final db = ActionIoJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await expectLater(
      db.transaction(() async {
        await db.into(db.actionIoSessions).insert(session('execution'));
        throw StateError('simulated admission failure');
      }),
      throwsStateError,
    );
    expect(await db.select(db.actionIoSessions).get(), isEmpty);
  });

  test('input IDs and sequences cannot be reused within an execution', () async {
    final db = ActionIoJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.actionIoSessions).insert(session('execution'));
    ActionIoMessagesCompanion message(String id, int sequence) => ActionIoMessagesCompanion.insert(
      executionId: 'execution',
      messageId: id,
      sequence: sequence,
      fingerprint: 'fingerprint',
      closesInput: false,
      deliveryState: 'accepted',
      inputBytes: 0,
      admittedAt: DateTime.utc(2026, 10, 28),
    );
    await db.into(db.actionIoMessages).insert(message('first', 0));
    await expectLater(db.into(db.actionIoMessages).insert(message('second', 0)), throwsA(isA<Exception>()));
    await expectLater(db.into(db.actionIoMessages).insert(message('first', 1)), throwsA(isA<Exception>()));
    expect(await db.select(db.actionIoMessages).get(), hasLength(1));
  });
}
