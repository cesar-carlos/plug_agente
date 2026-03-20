/// Splits [sql] at top-level `;` boundaries for separate authorization.
///
/// Not a full SQL parser: respects `'...'`, `"..."`, `[...]`, `--` line comments,
/// and `/* */` block comments so semicolons inside literals do not split.
List<String> splitSqlStatements(String sql) {
  final out = <String>[];
  final buf = StringBuffer();
  var i = 0;
  var inSingle = false;
  var inDouble = false;
  var inBracket = false;

  void flush() {
    final trimmed = buf.toString().trim();
    if (trimmed.isNotEmpty) {
      out.add(trimmed);
    }
    buf.clear();
  }

  while (i < sql.length) {
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
      flush();
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

  flush();
  return out;
}
