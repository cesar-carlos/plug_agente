import 'package:plug_agente/core/utils/sql_text_scanner.dart';

/// Splits [sql] at top-level `;` boundaries and SQL Server `GO` batch
/// separators for separate authorization.
///
/// Not a full SQL parser: respects `'...'`, `"..."`, `[...]`, `--` line comments,
/// and `/* */` block comments so semicolons inside literals do not split.
///
/// A line whose code-only content is `GO` (any case) is treated as a batch
/// separator. Does not handle MySQL backtick strings or PostgreSQL dollar-quoting.
List<String> splitSqlStatements(String sql) {
  final out = <String>[];
  _scanTopLevelSqlStatements(sql, (trimmed) {
    out.add(trimmed);
    return false;
  });
  return out;
}

/// Whether [sql] contains more than one non-empty top-level statement.
///
/// Uses the same scan rules as [splitSqlStatements] (literals, comments, `GO`).
/// Stops scanning once a second non-empty statement is found.
bool sqlHasMultipleTopLevelStatements(String sql) {
  var nonEmptySegments = 0;
  _scanTopLevelSqlStatements(sql, (_) {
    nonEmptySegments++;
    return nonEmptySegments > 1;
  });
  return nonEmptySegments > 1;
}

/// Top-level SQL fragments for `sql.execute` with `multi_result` and
/// client-token authorization.
///
/// Performs a single [splitSqlStatements] pass. When every fragment is empty
/// (e.g. `;;;`), returns `[originalSql]` so authorization still runs once.
List<String> sqlStatementsForClientTokenAuthorization(String sql) {
  final parts = splitSqlStatements(sql);
  return parts.isEmpty ? <String>[sql] : parts;
}

/// Returns true from [onNonEmptySegment] to stop scanning early.
void _scanTopLevelSqlStatements(
  String sql,
  bool Function(String trimmed) onNonEmptySegment,
) {
  final buf = StringBuffer();
  var stmtLineStart = 0;
  final lineCode = StringBuffer();
  var stop = false;

  bool flush() {
    final trimmed = buf.toString().trim();
    buf.clear();
    stmtLineStart = 0;
    lineCode.clear();
    if (trimmed.isEmpty) {
      return false;
    }
    return onNonEmptySegment(trimmed);
  }

  void discardCurrentLine() {
    final text = buf.toString();
    buf
      ..clear()
      ..write(text.substring(0, stmtLineStart));
  }

  void handleEndOfLine() {
    if (lineCode.toString().trim().toUpperCase() == 'GO') {
      discardCurrentLine();
      stop = flush();
    } else {
      stmtLineStart = buf.length;
    }
    lineCode.clear();
  }

  void writeCodeRange(int start, int end) {
    var i = start;
    while (i < end && !stop) {
      final c = sql[i];
      if (c == ';') {
        stop = flush();
        i++;
        continue;
      }
      if (c == '\n' || c == '\r') {
        buf.write(c);
        i++;
        if (c == '\r' && i < end && sql[i] == '\n') {
          buf.write('\n');
          i++;
        }
        handleEndOfLine();
        continue;
      }
      buf.write(c);
      lineCode.write(c);
      i++;
    }
  }

  scanSqlText(
    sql,
    onCode: writeCodeRange,
    onLiteral: (start, end) {
      if (stop) {
        return;
      }
      buf.write(sql.substring(start, end));
    },
    onComment: (start, end, {required isBlock}) {
      if (stop) {
        return;
      }
      buf.write(sql.substring(start, end));
    },
  );

  if (!stop && lineCode.toString().trim().toUpperCase() == 'GO') {
    discardCurrentLine();
  }
  if (!stop) {
    flush();
  }
}
