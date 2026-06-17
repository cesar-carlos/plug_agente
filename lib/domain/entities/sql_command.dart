/// SQL command with optional parameters.
class SqlCommand {
  const SqlCommand({
    required this.sql,
    this.params,
  });

  /// SQL query string.
  final String sql;

  /// Optional query parameters.
  final Map<String, dynamic>? params;
}

/// Result of executing a single SQL command.
class SqlCommandResult {
  const SqlCommandResult({
    required this.index,
    required this.ok,
    this.rows,
    this.rowCount,
    this.affectedRows,
    this.error,
    this.columnMetadata,
  });

  factory SqlCommandResult.success({
    required int index,
    required List<Map<String, dynamic>> rows,
    int? rowCount,
    int? affectedRows,
    List<Map<String, dynamic>>? columnMetadata,
  }) {
    return SqlCommandResult(
      index: index,
      ok: true,
      rows: rows,
      rowCount: rowCount ?? rows.length,
      affectedRows: affectedRows,
      columnMetadata: columnMetadata,
    );
  }

  factory SqlCommandResult.failure({
    required int index,
    required String error,
  }) {
    return SqlCommandResult(
      index: index,
      ok: false,
      error: error,
    );
  }

  /// Command index in batch.
  final int index;

  /// Whether execution succeeded.
  final bool ok;

  /// Result rows (on success).
  final List<Map<String, dynamic>>? rows;

  /// Number of rows returned.
  final int? rowCount;

  /// Number of rows affected (INSERT/UPDATE/DELETE).
  final int? affectedRows;

  /// Error message (on failure).
  final String? error;

  /// Column metadata.
  final List<Map<String, dynamic>>? columnMetadata;
}

/// Options for SQL execution.
class SqlExecutionOptions {
  const SqlExecutionOptions({
    this.timeoutMs = 30000,
    this.maxRows = 50000,
    this.transaction = false,
    this.maxParallelReadOnlyBatchItems = 1,
  });

  /// Query timeout in milliseconds.
  final int timeoutMs;

  /// Maximum number of rows to return.
  final int maxRows;

  /// Whether to execute in a transaction (batch only).
  final bool transaction;

  /// Opt-in parallelism for independent read-only batch commands.
  final int maxParallelReadOnlyBatchItems;
}
