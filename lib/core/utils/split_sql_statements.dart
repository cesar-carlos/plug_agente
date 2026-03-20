/// Splits [sql] at top-level `;` boundaries for separate authorization.
///
/// Not a full SQL parser: respects `'...'`, `"..."`, `[...]`, `--` line comments,
/// and `/* */` block comments so semicolons inside literals do not split.
///
/// Does not handle MySQL backtick strings, PostgreSQL dollar-quoting, or
/// SQL Server `GO` batch separators.
List<String> splitSqlStatements(String sql) {
  final out = <String>[];
  _scanTopLevelSqlStatements(sql, (String trimmed) {
    out.add(trimmed);
    return false;
  });
  return out;
}

/// Whether [sql] contains more than one non-empty top-level statement.
///
/// Uses the same scan rules as [splitSqlStatements] (literals and comments).
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
  var i = 0;
  var inSingle = false;
  var inDouble = false;
  var inBracket = false;
  var stop = false;

  bool flush() {
    final trimmed = buf.toString().trim();
    buf.clear();
    if (trimmed.isEmpty) {
      return false;
    }
    return onNonEmptySegment(trimmed);
  }

  while (i < sql.length && !stop) {
    final c = sql[i];

    if (inBracket) {
      buf.write(c);
      if (c == ']') {
        inBracket = false;
      }
      i++;
      continue;
    }

    if (inSingle) {
      buf.write(c);
      if (c == "'") {
        if (i + 1 < sql.length && sql[i + 1] == "'") {
          buf.write(sql[i + 1]);
          i += 2;
          continue;
        }
        inSingle = false;
      }
      i++;
      continue;
    }

    if (inDouble) {
      buf.write(c);
      if (c == '"') {
        if (i + 1 < sql.length && sql[i + 1] == '"') {
          buf.write(sql[i + 1]);
          i += 2;
          continue;
        }
        inDouble = false;
      }
      i++;
      continue;
    }

    if (c == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      buf.write(c);
      buf.write(sql[i + 1]);
      i += 2;
      while (i < sql.length) {
        final ch = sql[i];
        if (ch == '\n' || ch == '\r') {
          break;
        }
        buf.write(ch);
        i++;
      }
      continue;
    }

    if (c == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      buf.write(c);
      buf.write(sql[i + 1]);
      i += 2;
      while (i + 1 < sql.length) {
        if (sql[i] == '*' && sql[i + 1] == '/') {
          buf.write('*');
          buf.write('/');
          i += 2;
          break;
        }
        buf.write(sql[i]);
        i++;
      }
      continue;
    }

    if (c == ';') {
      stop = flush();
      i++;
      continue;
    }

    if (c == '[') {
      inBracket = true;
      buf.write(c);
      i++;
      continue;
    }

    if (c == "'") {
      inSingle = true;
      buf.write(c);
      i++;
      continue;
    }

    if (c == '"') {
      inDouble = true;
      buf.write(c);
      i++;
      continue;
    }

    buf.write(c);
    i++;
  }

  if (!stop) {
    flush();
  }
}
