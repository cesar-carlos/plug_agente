/// Shared walk over SQL text for quotes, brackets, and comments.
///
/// Not a full SQL parser: no MySQL backticks, PostgreSQL dollar-quoting, or
/// nested block comments. Callers must not diverge from these quoting rules.
void scanSqlText(
  String sql, {
  required void Function(int start, int end) onCode,
  required void Function(int start, int end) onLiteral,
  required void Function(int start, int end, {required bool isBlock}) onComment,
}) {
  var i = 0;
  var codeStart = 0;

  void flushCode(int end) {
    if (end > codeStart) {
      onCode(codeStart, end);
    }
  }

  while (i < sql.length) {
    final c = sql[i];

    if (c == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      flushCode(i);
      final start = i;
      i += 2;
      while (i < sql.length) {
        final ch = sql[i];
        if (ch == '\n' || ch == '\r') {
          break;
        }
        i++;
      }
      onComment(start, i, isBlock: false);
      codeStart = i;
      continue;
    }

    if (c == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      flushCode(i);
      final start = i;
      i += 2;
      var closed = false;
      while (i + 1 < sql.length) {
        if (sql[i] == '*' && sql[i + 1] == '/') {
          i += 2;
          closed = true;
          break;
        }
        i++;
      }
      if (!closed) {
        i = sql.length;
      }
      onComment(start, i, isBlock: true);
      codeStart = i;
      continue;
    }

    if (c == '[') {
      flushCode(i);
      final start = i;
      i++;
      while (i < sql.length && sql[i] != ']') {
        i++;
      }
      if (i < sql.length) {
        i++;
      }
      onLiteral(start, i);
      codeStart = i;
      continue;
    }

    if (c == "'") {
      flushCode(i);
      final start = i;
      i = _scanQuotedLiteral(sql, i, "'");
      onLiteral(start, i);
      codeStart = i;
      continue;
    }

    if (c == '"') {
      flushCode(i);
      final start = i;
      i = _scanQuotedLiteral(sql, i, '"');
      onLiteral(start, i);
      codeStart = i;
      continue;
    }

    i++;
  }

  flushCode(i);
}

int _scanQuotedLiteral(String sql, int openIndex, String quote) {
  var i = openIndex + 1;
  while (i < sql.length) {
    if (sql[i] == quote) {
      if (i + 1 < sql.length && sql[i + 1] == quote) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return sql.length;
}
