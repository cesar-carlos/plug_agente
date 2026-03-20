/// SQL command with optional parameters.
class SqlCommand {
  const SqlCommand({
    required this.sql,
    this.params,
  });

  factory SqlCommand.fromJson(Map<String, dynamic> json) {
    return SqlCommand(
      sql: json['sql'] as String,
      params: json['params'] as Map<String, dynamic>?,
    );
  }

  /// SQL query string.
  final String sql;

  /// Optional query parameters.
  final Map<String, dynamic>? params;

  Map<String, dynamic> toJson() {
    return {
      'sql': sql,
      if (params != null) 'params': params,
    };
  }
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

  factory SqlCommandResult.fromJson(Map<String, dynamic> json) {
    return SqlCommandResult(
      index: json['index'] as int,
      ok: json['ok'] as bool,
      rows: json['rows'] != null
          ? (json['rows'] as List<dynamic>)
                .map((e) => e as Map<String, dynamic>)
                .toList()
          : null,
      rowCount: json['row_count'] as int? ?? json['rowCount'] as int?,
      affectedRows:
          json['affected_rows'] as int? ?? json['affectedRows'] as int?,
      error: json['error'] as String?,
      columnMetadata: json['column_metadata'] != null
          ? (json['column_metadata'] as List<dynamic>)
                .map((e) => e as Map<String, dynamic>)
                .toList()
          : json['columnMetadata'] != null
          ? (json['columnMetadata'] as List<dynamic>)
                .map((e) => e as Map<String, dynamic>)
                .toList()
          : null,
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

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'ok': ok,
      if (rows != null) 'rows': rows,
      if (rowCount != null) 'row_count': rowCount,
      if (affectedRows != null) 'affected_rows': affectedRows,
      if (error != null) 'error': error,
      if (columnMetadata != null) 'column_metadata': columnMetadata,
    };
  }
}

/// Options for SQL execution.
class SqlExecutionOptions {
  const SqlExecutionOptions({
    this.timeoutMs = 30000,
    this.maxRows = 50000,
    this.transaction = false,
  });

  factory SqlExecutionOptions.fromJson(Map<String, dynamic> json) {
    return SqlExecutionOptions(
      timeoutMs: json['timeout_ms'] as int? ?? 30000,
      maxRows: json['max_rows'] as int? ?? 50000,
      transaction: json['transaction'] as bool? ?? false,
    );
  }

  /// Query timeout in milliseconds.
  final int timeoutMs;

  /// Maximum number of rows to return.
  final int maxRows;

  /// Whether to execute in a transaction (batch only).
  final bool transaction;

  Map<String, dynamic> toJson() {
    return {
      'timeout_ms': timeoutMs,
      'max_rows': maxRows,
      'transaction': transaction,
    };
  }
}
