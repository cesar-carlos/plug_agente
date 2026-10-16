enum SqlOperationJournalState { executing, completed, rolledBack, outcomeUnknown, cancellationRequested, cancelled }

/// Safe categorical metadata only; never a native message, SQL or parameter.
enum SqlOperationFailureCode {
  sourceIdentityMismatch('SOURCE_IDENTITY_MISMATCH'),
  sourceStructureMismatch('SOURCE_STRUCTURE_MISMATCH'),
  conditionFailed('SQL_OPERATION_CONDITION_FAILED'),
  rowLimit('SQL_OPERATION_ROW_LIMIT'),
  rowCountUnknown('SQL_OPERATION_ROW_COUNT_UNKNOWN'),
  outputInvalid('SQL_OPERATION_OUTPUT_INVALID'),
  authorizationChanged('SQL_OPERATION_AUTHORIZATION_CHANGED'),
  authorizationDenied('SQL_OPERATION_AUTHORIZATION_DENIED'),
  cancelled('SQL_OPERATION_CANCELLED'),
  nativeFailed('SQL_OPERATION_NATIVE_FAILED'),
  timeout('SQL_OPERATION_TIMEOUT'),
  interrupted('SQL_OPERATION_INTERRUPTED'),
  failed('SQL_OPERATION_FAILED');

  const SqlOperationFailureCode(this.code);
  final String code;
  static SqlOperationFailureCode? tryParse(String code) {
    for (final value in values) {
      if (value.code == code) return value;
    }
    return null;
  }
}

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
    this.failureCode,
  });
  final String operationId;
  final String scopeHash;
  final String fingerprint;
  final String executionId;
  final SqlOperationJournalState state;
  final DateTime updatedAt;
  final int? directlyAffectedRows;
  final String? contentHash;
  final SqlOperationFailureCode? failureCode;
}

class SqlOperationClaim {
  const SqlOperationClaim({required this.entry, required this.claimed});
  final SqlOperationJournalEntry entry;
  final bool claimed;
}
