import 'package:drift/drift.dart';

part 'sql_operation_journal_database.g.dart';

class SqlOperationJournalRecords extends Table {
  TextColumn get operationId => text()();
  TextColumn get scopeHash => text()();
  TextColumn get fingerprint => text()();
  TextColumn get contentHash => text().nullable()();
  TextColumn get executionId => text()();
  TextColumn get state => text()();
  IntColumn get directlyAffectedRows => integer().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

/// Separate from the business DB and existing agent data; never reset on upgrade.
@DriftDatabase(tables: [SqlOperationJournalRecords])
class SqlOperationJournalDatabase extends _$SqlOperationJournalDatabase {
  SqlOperationJournalDatabase(super.e);
  @override
  int get schemaVersion => 2;
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(sqlOperationJournalRecords, sqlOperationJournalRecords.contentHash);
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA journal_mode = WAL');
      // An acknowledged intent must survive a process/power failure before dispatch.
      await customStatement('PRAGMA synchronous = FULL');
      await customStatement('PRAGMA busy_timeout = 5000');
    },
  );
}
