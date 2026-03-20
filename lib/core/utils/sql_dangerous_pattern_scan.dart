/// Detects SQL comment markers and `;keyword` sequences only at statement
/// boundaries, respecting `'...'`, `"..."`, `[...]` using the same scan rules as
/// `splitSqlStatements` in `split_sql_statements.dart`.
///
/// Returns true when top-level `--`, `/*`, or `;` followed by a dangerous
/// keyword (drop, delete, insert, update, alter, create, truncate) appears
/// outside string/bracket literals.
bool sqlContainsTopLevelDangerousPatterns(String sql) {
  var i = 0;
  var inSingle = false;
  var inDouble = false;
  var inBracket = false;

  while (i < sql.length) {
    final c = sql[i];

    if (inBracket) {
      if (c == ']') {
        inBracket = false;
      }
      i++;
      continue;
    }

    if (inSingle) {
      if (c == "'") {
        if (i + 1 < sql.length && sql[i + 1] == "'") {
          i += 2;
          continue;
        }
        inSingle = false;
      }
      i++;
      continue;
    }

    if (inDouble) {
      if (c == '"') {
        if (i + 1 < sql.length && sql[i + 1] == '"') {
          i += 2;
          continue;
        }
        inDouble = false;
      }
      i++;
      continue;
    }

    if (c == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      return true;
    }

    if (c == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      return true;
    }

    if (c == ';') {
      var j = i + 1;
      while (j < sql.length) {
        final ch = sql[j];
        if (ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') {
          break;
        }
        j++;
      }
      if (_dangerousKeywordFollows(sql, j)) {
        return true;
      }
      i++;
      continue;
    }

    if (c == '[') {
      inBracket = true;
      i++;
      continue;
    }

    if (c == "'") {
      inSingle = true;
      i++;
      continue;
    }

    if (c == '"') {
      inDouble = true;
      i++;
      continue;
    }

    i++;
  }

  return false;
}

const List<String> _sqlDangerousKeywords = [
  'drop',
  'delete',
  'insert',
  'update',
  'alter',
  'create',
  'truncate',
];

bool _dangerousKeywordFollows(String sql, int j) {
  if (j >= sql.length) {
    return false;
  }
  final lower = sql.toLowerCase();
  for (final kw in _sqlDangerousKeywords) {
    if (j + kw.length > lower.length) {
      continue;
    }
    var matches = true;
    for (var k = 0; k < kw.length; k++) {
      if (lower.codeUnitAt(j + k) != kw.codeUnitAt(k)) {
        matches = false;
        break;
      }
    }
    if (!matches) {
      continue;
    }
    if (j > 0 && _isSqlIdentChar(lower.codeUnitAt(j - 1))) {
      continue;
    }
    final after = j + kw.length;
    if (after < lower.length && _isSqlIdentChar(lower.codeUnitAt(after))) {
      continue;
    }
    return true;
  }
  return false;
}

bool _isSqlIdentChar(int u) =>
    (u >= 0x41 && u <= 0x5a) ||
    (u >= 0x61 && u <= 0x7a) ||
    (u >= 0x30 && u <= 0x39) ||
    u == 0x5f;
