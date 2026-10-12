enum SqlOperationJournalState { executing, completed, rolledBack, outcomeUnknown, cancellationRequested, cancelled }

class SqlOperationJournalEntry {
  const SqlOperationJournalEntry({
    required this.operationId,
    required this.scopeHash,
    required this.fingerprint,
    required this.executionId,
    required this.state,
    required this.updatedAt,
    this.directlyAffectedRows,
    this.contentHash,
  });
  final String operationId;
  final String scopeHash;
  final String fingerprint;
  final String executionId;
  final SqlOperationJournalState state;
  final DateTime updatedAt;
  final int? directlyAffectedRows;
  final String? contentHash;
}

class SqlOperationClaim {
  const SqlOperationClaim({required this.entry, required this.claimed});
  final SqlOperationJournalEntry entry;
  final bool claimed;
}
