import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/infrastructure/stores/drift_sql_operation_journal.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = 'a' * 64;
  final fingerprint = 'b' * 64;
  SqlOperationJournalEntry intent({String id = 'operation', String? hash}) => SqlOperationJournalEntry(
    operationId: id,
    scopeHash: scope,
    fingerprint: hash ?? fingerprint,
    contentHash: 'c' * 64,
    executionId: 'execution',
    state: SqlOperationJournalState.executing,
    updatedAt: DateTime.utc(2026, 10, 10),
  );
  test('duplicate claims never authorize a second dispatch', () async {
    final db = SqlOperationJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final journal = DriftSqlOperationJournal(db);
    final results = await Future.wait([journal.claim(intent()), journal.claim(intent())]);
    expect(results.where((r) => r.getOrThrow().claimed), hasLength(1));
    expect(results.every((r) => r.isSuccess()), isTrue);
  });
  test('operation id cannot be reused with another content or source/token scope', () async {
    final db = SqlOperationJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final journal = DriftSqlOperationJournal(db);
    await journal.claim(intent());
    final changed = await journal.claim(intent(hash: 'c' * 64));
    expect(changed.exceptionOrNull(), isA<SqlOperationFailure>());
    expect((changed.exceptionOrNull()! as SqlOperationFailure).code, 'SQL_OPERATION_CONFLICT');
    expect((await journal.get('operation', 'c' * 64, fingerprint)).isError(), isTrue);
  });
  test('cancel request is not rollback and commit may still complete', () async {
    final db = SqlOperationJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final journal = DriftSqlOperationJournal(db);
    await journal.claim(intent());
    final requested = (await journal.requestCancellation('operation', scope, fingerprint)).getOrThrow();
    expect(requested.state, SqlOperationJournalState.cancellationRequested);
    final done = (await journal.finish(
      'operation',
      scope,
      fingerprint,
      SqlOperationJournalState.completed,
      directlyAffectedRows: 1,
    )).getOrThrow();
    expect(done.state, SqlOperationJournalState.completed);
    expect((await journal.claim(intent())).getOrThrow().claimed, isFalse);
  });
  test('unknown and terminal states never return to executing or change receipts', () async {
    final db = SqlOperationJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final journal = DriftSqlOperationJournal(db);
    await journal.claim(intent());
    await journal.finish('operation', scope, fingerprint, SqlOperationJournalState.outcomeUnknown);
    expect((await journal.claim(intent())).getOrThrow().claimed, isFalse);
    expect(
      (await journal.finish(
        'operation',
        scope,
        fingerprint,
        SqlOperationJournalState.completed,
        directlyAffectedRows: 1,
      )).isError(),
      isTrue,
    );
  });
  test('rejects success without a reliable direct affected-row count', () async {
    final db = SqlOperationJournalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final journal = DriftSqlOperationJournal(db);
    await journal.claim(intent());
    expect(
      (await journal.finish('operation', scope, fingerprint, SqlOperationJournalState.completed)).isError(),
      isTrue,
    );
  });
  test('restart persists intent, records uncertainty, and preserves completed operations', () async {
    final directory = await Directory.systemTemp.createTemp('sql_operation_journal_test_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/journal.sqlite');
    var db = SqlOperationJournalDatabase(NativeDatabase(file));
    var journal = DriftSqlOperationJournal(db);
    await journal.claim(intent());
    await journal.claim(intent(id: 'completed'));
    await journal.finish('completed', scope, fingerprint, SqlOperationJournalState.completed, directlyAffectedRows: 2);
    await db.close();
    db = SqlOperationJournalDatabase(NativeDatabase(file));
    addTearDown(db.close);
    journal = DriftSqlOperationJournal(db);
    expect((await journal.recoverInterrupted()).getOrThrow(), 1);
    expect(
      (await journal.get('operation', scope, fingerprint)).getOrThrow().state,
      SqlOperationJournalState.outcomeUnknown,
    );
    expect((await journal.get('completed', scope, fingerprint)).getOrThrow().directlyAffectedRows, 2);
    expect((await journal.claim(intent())).getOrThrow().claimed, isFalse);
    expect((await journal.recoverInterrupted()).getOrThrow(), 0);
    expect((await db.customSelect('PRAGMA synchronous').getSingle()).read<int>('synchronous'), 2);
  });
}
