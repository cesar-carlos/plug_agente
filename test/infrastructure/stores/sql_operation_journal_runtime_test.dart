import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_runtime.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('additive schema v1 upgrade preserves existing rows; startup recovery does not reexecute them', () async {
    final directory = await Directory.systemTemp.createTemp('sql_operation_upgrade_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/journal.db';
    final legacy = sqlite3.open(path);
    legacy.execute(
      'CREATE TABLE sql_operation_journal_records (operation_id TEXT NOT NULL PRIMARY KEY, scope_hash TEXT NOT NULL, fingerprint TEXT NOT NULL, execution_id TEXT NOT NULL, state TEXT NOT NULL, directly_affected_rows INTEGER NULL, updated_at INTEGER NOT NULL)',
    );
    legacy.execute('INSERT INTO sql_operation_journal_records VALUES (?, ?, ?, ?, ?, ?, ?)', [
      'existing',
      'a' * 64,
      'b' * 64,
      'execution',
      'executing',
      null,
      DateTime.utc(2026).millisecondsSinceEpoch ~/ 1000,
    ]);
    legacy.execute('PRAGMA user_version = 1');
    legacy.close();
    final runtime = SqlOperationJournalRuntime(path);
    addTearDown(runtime.close);
    expect((await runtime.initialize()).isSuccess(), isTrue);
    final row = (await runtime.journal.get('existing', 'a' * 64, 'b' * 64)).getOrThrow();
    expect(row.state, SqlOperationJournalState.outcomeUnknown);
    expect(row.contentHash, isNull);
    expect(
      (await runtime.journal.claim(
        SqlOperationJournalEntry(
          operationId: 'existing',
          scopeHash: 'a' * 64,
          fingerprint: 'b' * 64,
          contentHash: 'c' * 64,
          executionId: 'new',
          state: SqlOperationJournalState.executing,
          updatedAt: DateTime.now(),
        ),
      )).isError(),
      isTrue,
    );
    await runtime.close();
    final reopened = SqlOperationJournalRuntime(path);
    addTearDown(reopened.close);
    expect((await reopened.initialize()).isSuccess(), isTrue);
    expect(
      (await reopened.journal.get('existing', 'a' * 64, 'b' * 64)).getOrThrow().state,
      SqlOperationJournalState.outcomeUnknown,
    );
  });
  test('unavailable journal fails closed before exposing storage', () async {
    final directory = await Directory.systemTemp.createTemp('sql_operation_missing_');
    addTearDown(() => directory.delete(recursive: true));
    final runtime = SqlOperationJournalRuntime('${directory.path}/missing/journal.db');
    addTearDown(runtime.close);
    expect((await runtime.initialize()).isError(), isTrue);
    expect(() => runtime.journal, throwsStateError);
  });
}
