import 'package:plug_agente/domain/entities/sql_operation_journal_entry.dart';
import 'package:result_dart/result_dart.dart';

/// Durable metadata only. Intent must commit before business SQL starts.
abstract class ISqlOperationJournal {
  Future<Result<SqlOperationClaim>> claim(SqlOperationJournalEntry intent);
  Future<Result<SqlOperationJournalEntry>> get(String operationId, String scopeHash, String fingerprint);
  Future<Result<SqlOperationJournalEntry>> finish(
    String operationId,
    String scopeHash,
    String fingerprint,
    SqlOperationJournalState state, {
    int? directlyAffectedRows,
    SqlOperationFailureCode? failureCode,
  });
  Future<Result<SqlOperationJournalEntry>> requestCancellation(
    String operationId,
    String scopeHash,
    String fingerprint,
  );

  /// Called once at process startup, before accepting work. Never makes a record executable.
  Future<Result<int>> recoverInterrupted();
}
