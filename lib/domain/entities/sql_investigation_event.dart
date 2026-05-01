/// Kind of SQL investigation entry shown in the dashboard diagnostics feed.
enum SqlInvestigationKind {
  authorizationDenied,
  executionError,
}

/// A single SQL-related diagnostic event (authorization denial or execution failure).
class SqlInvestigationEvent {
  const SqlInvestigationEvent({
    required this.timestamp,
    required this.kind,
    required this.method,
    required this.originalSql,
    this.rpcRequestId,
    this.internalQueryId,
    this.reason,
    this.clientId,
    this.operation,
    this.resource,
    this.effectiveSql,
    this.errorMessage,
    this.executedInDb = false,
  });

  final DateTime timestamp;
  final SqlInvestigationKind kind;
  final String method;
  final String originalSql;
  final String? rpcRequestId;
  final String? internalQueryId;
  final String? reason;
  final String? clientId;
  final String? operation;
  final String? resource;
  final String? effectiveSql;
  final String? errorMessage;
  final bool executedInDb;
}
