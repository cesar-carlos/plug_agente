import 'dart:io';
import 'package:drift/native.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/domain/repositories/i_sql_operation_journal.dart';
import 'package:plug_agente/infrastructure/stores/drift_sql_operation_journal.dart';
import 'package:plug_agente/infrastructure/stores/sql_operation_journal_database.dart';
import 'package:result_dart/result_dart.dart';

/// An exclusive process lock prevents recovery from relabeling another live agent's work.
class SqlOperationJournalRuntime {
  SqlOperationJournalRuntime(this.path);
  final String path;
  RandomAccessFile? _ownerLock;
  SqlOperationJournalDatabase? _database;
  ISqlOperationJournal? _journal;
  Future<Result<void>>? _initializing;
  ISqlOperationJournal get journal => _journal ?? (throw StateError('SQL operation journal not initialized.'));
  Future<Result<void>> initialize() => _initializing ??= _open();
  Future<Result<void>> _open() async {
    try {
      _ownerLock = await File('$path.owner.lock').open(mode: FileMode.append);
      await _ownerLock!.lock();
      final database = SqlOperationJournalDatabase(NativeDatabase.createInBackground(File(path)));
      _database = database;
      final journal = DriftSqlOperationJournal(database);
      (await journal.recoverInterrupted()).getOrThrow();
      _journal = journal;
      return const Success(unit);
    } on Object catch (_) {
      var cleanupFailed = false;
      try {
        await close();
      } on Object {
        cleanupFailed = true;
      }
      return Failure(
        SqlOperationFailure(
          code: 'SQL_OPERATION_JOURNAL_UNAVAILABLE',
          context: {if (cleanupFailed) 'cleanup_failed': true},
          message: 'Durable journal storage is unavailable or owned by another process.',
        ),
      );
    }
  }

  Future<void> close() async {
    final database = _database;
    final owner = _ownerLock;
    _database = null;
    _ownerLock = null;
    _journal = null;
    try {
      await database?.close();
    } finally {
      await owner?.close();
    }
  }
}
