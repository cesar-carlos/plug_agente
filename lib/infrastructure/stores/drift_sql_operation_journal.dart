import 'package:drift/drift.dart';
import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_journal.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_database.dart';
import 'package:result_dart/result_dart.dart';

class DriftSqlOperationJournal implements ISqlOperationJournal {
  DriftSqlOperationJournal(this._db, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final SqlOperationJournalDatabase _db;
  final DateTime Function() _now;

  @override
  Future<Result<SqlOperationClaim>> claim(SqlOperationJournalEntry intent) => _guard(
    () => _db.transaction(() async {
      if (intent.contentHash == null ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(intent.contentHash!) ||
          intent.state != SqlOperationJournalState.executing ||
          intent.failureCode != null ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(intent.scopeHash) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(intent.fingerprint) ||
          intent.operationId.isEmpty ||
          intent.executionId.isEmpty) {
        throw SqlOperationFailure(code: 'SQL_OPERATION_INVALID', message: 'Invalid operation intent.');
      }
      final inserted = await _db
          .into(_db.sqlOperationJournalRecords)
          .insert(
            SqlOperationJournalRecordsCompanion.insert(
              operationId: intent.operationId,
              scopeHash: intent.scopeHash,
              fingerprint: intent.fingerprint,
              executionId: intent.executionId,
              contentHash: Value(intent.contentHash),
              state: intent.state.name,
              updatedAt: intent.updatedAt,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final stored = await _entry(intent.operationId, intent.scopeHash, intent.fingerprint);
      if (stored.contentHash != intent.contentHash) {
        throw SqlOperationFailure(code: 'SQL_OPERATION_CONFLICT', message: 'Operation content changed.');
      }
      // sqlite last_insert_rowid is not a reliable indicator after IGNORE.
      final changed = await _db.customSelect('SELECT changes() AS n').getSingle();
      return SqlOperationClaim(entry: stored, claimed: inserted != 0 && changed.read<int>('n') == 1);
    }),
  );

  @override
  Future<Result<SqlOperationJournalEntry>> get(String operationId, String scopeHash, String fingerprint) =>
      _guard(() => _entry(operationId, scopeHash, fingerprint));

  @override
  Future<Result<SqlOperationJournalEntry>> finish(
    String operationId,
    String scopeHash,
    String fingerprint,
    SqlOperationJournalState state, {
    int? directlyAffectedRows,
    SqlOperationFailureCode? failureCode,
  }) => _guard(
    () => _db.transaction(() async {
      final current = await _entry(operationId, scopeHash, fingerprint);
      if (![
            SqlOperationJournalState.executing,
            SqlOperationJournalState.cancellationRequested,
          ].contains(current.state) ||
          ![
            SqlOperationJournalState.completed,
            SqlOperationJournalState.rolledBack,
            SqlOperationJournalState.outcomeUnknown,
            SqlOperationJournalState.cancelled,
          ].contains(state) ||
          (state == SqlOperationJournalState.completed && (directlyAffectedRows == null || directlyAffectedRows < 0)) ||
          (state != SqlOperationJournalState.completed && directlyAffectedRows != null) ||
          (state == SqlOperationJournalState.completed && failureCode != null)) {
        throw SqlOperationFailure(code: 'SQL_OPERATION_CONFLICT', message: 'Invalid operation transition.');
      }
      await (_db.update(_db.sqlOperationJournalRecords)..where((r) => r.operationId.equals(operationId))).write(
        SqlOperationJournalRecordsCompanion(
          state: Value(state.name),
          directlyAffectedRows: Value(directlyAffectedRows),
          failureCode: Value(failureCode?.code),
          updatedAt: Value(_now()),
        ),
      );
      return _entry(operationId, scopeHash, fingerprint);
    }),
  );

  @override
  Future<Result<SqlOperationJournalEntry>> requestCancellation(
    String operationId,
    String scopeHash,
    String fingerprint,
  ) => _guard(
    () => _db.transaction(() async {
      final current = await _entry(operationId, scopeHash, fingerprint);
      if (current.state == SqlOperationJournalState.executing) {
        await (_db.update(_db.sqlOperationJournalRecords)..where((r) => r.operationId.equals(operationId))).write(
          SqlOperationJournalRecordsCompanion(
            state: Value(SqlOperationJournalState.cancellationRequested.name),
            updatedAt: Value(_now()),
          ),
        );
      }
      return _entry(operationId, scopeHash, fingerprint);
    }),
  );

  @override
  Future<Result<int>> recoverInterrupted() => _guard(
    () async =>
        (_db.update(_db.sqlOperationJournalRecords)..where(
              (r) => r.state.isIn([
                SqlOperationJournalState.executing.name,
                SqlOperationJournalState.cancellationRequested.name,
              ]),
            ))
            .write(
              SqlOperationJournalRecordsCompanion(
                state: Value(SqlOperationJournalState.outcomeUnknown.name),
                failureCode: Value(SqlOperationFailureCode.interrupted.code),
                updatedAt: Value(_now()),
              ),
            ),
  );

  Future<SqlOperationJournalEntry> _entry(String id, String scopeHash, String fingerprint) async {
    final row = await (_db.select(
      _db.sqlOperationJournalRecords,
    )..where((r) => r.operationId.equals(id))).getSingleOrNull();
    if (row == null || row.scopeHash != scopeHash || row.fingerprint != fingerprint) {
      throw SqlOperationFailure(
        code: 'SQL_OPERATION_CONFLICT',
        message: 'Operation identity unavailable or content mismatch.',
      );
    }
    final failureCode = row.failureCode == null ? null : SqlOperationFailureCode.tryParse(row.failureCode!);
    if (row.failureCode != null && failureCode == null) {
      throw SqlOperationFailure(
        code: 'SQL_OPERATION_JOURNAL_UNAVAILABLE',
        message: 'Invalid journal failure metadata.',
      );
    }
    return SqlOperationJournalEntry(
      failureCode: failureCode,
      operationId: row.operationId,
      scopeHash: row.scopeHash,
      fingerprint: row.fingerprint,
      executionId: row.executionId,
      contentHash: row.contentHash,
      state: SqlOperationJournalState.values.byName(row.state),
      updatedAt: row.updatedAt,
      directlyAffectedRows: row.directlyAffectedRows,
    );
  }

  Future<Result<T>> _guard<T extends Object>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on SqlOperationFailure catch (failure) {
      return Failure(failure);
    } on Exception catch (cause) {
      return Failure(
        SqlOperationFailure(
          code: 'SQL_OPERATION_JOURNAL_UNAVAILABLE',
          message: 'Durable operation journal unavailable.',
          cause: cause,
        ),
      );
    }
  }
}
