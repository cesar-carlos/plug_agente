import 'package:plug_agente/core/utils/sql_text_scanner.dart';

/// Detects leftover SQL comment markers and `;keyword` sequences only at
/// statement boundaries, respecting `'...'`, `"..."`, `[...]` using the same
/// scan rules as `splitSqlStatements`.
///
/// Callers that allow documentation comments should strip them first with
/// `stripTopLevelSqlComments`. Returns true when top-level `--`, `/*`, lock
/// hints, or `;` followed by a dangerous keyword (drop, delete, insert, update,
/// alter, create, truncate) appears outside string/bracket literals.
bool sqlContainsTopLevelDangerousPatterns(String sql) {
  final lower = sql.toLowerCase();
  var dangerous = false;
  scanSqlText(
    sql,
    onCode: (start, end) {
      if (dangerous) {
        return;
      }
      if (_codeRangeHasDangerousPatterns(lower, start, end)) {
        dangerous = true;
      }
    },
    onLiteral: (_, _) {},
    onComment: (_, _, {required isBlock}) {
      dangerous = true;
    },
  );
  return dangerous;
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

const List<String> _sqlLockHintKeywords = [
  'holdlock',
  'paglock',
  'serializable',
  'tablock',
  'tablockx',
  'updlock',
  'xlock',
];

bool _codeRangeHasDangerousPatterns(String lower, int start, int end) {
  var i = start;
  while (i < end) {
    final c = lower[i];
    if (c == ';') {
      var j = i + 1;
      while (j < end) {
        final ch = lower[j];
        if (ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r') {
          break;
        }
        j++;
      }
      if (_dangerousKeywordFollows(lower, j)) {
        return true;
      }
      i++;
      continue;
    }

    if (_isAsciiLetter(c.codeUnitAt(0)) && _lockHintFollows(lower, i)) {
      return true;
    }
    i++;
  }
  return false;
}

// Expects [lower] to be the pre-lowercased version of the original SQL string,
// ensuring index [j] aligns with the original scan position.
bool _dangerousKeywordFollows(String lower, int j) {
  if (j >= lower.length) {
    return false;
  }
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

// Expects [lower] to be the pre-lowercased version of the original SQL string.
bool _lockHintFollows(String lower, int j) {
  for (final kw in _sqlLockHintKeywords) {
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

bool _isAsciiLetter(int u) => (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a);

bool _isSqlIdentChar(int u) =>
    (u >= 0x41 && u <= 0x5a) || (u >= 0x61 && u <= 0x7a) || (u >= 0x30 && u <= 0x39) || u == 0x5f;
