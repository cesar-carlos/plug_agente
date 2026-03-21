/// Keyword boundary scan for lowercase SQL text used by `SqlOperationClassifier`.
///
/// Not a full lexer: word boundaries use the same identifier character set as the
/// classifier (ASCII letters, digits, `_`, `$`, `#`).
library;

final RegExp _sqlIdentifierPart = RegExp(
  r'[a-z0-9_$#]',
  caseSensitive: false,
);

bool sqlIdentifierPartChar(String sql, int index) {
  if (index < 0 || index >= sql.length) {
    return false;
  }
  return _sqlIdentifierPart.hasMatch(sql[index]);
}

bool sqlIsWordBoundary(String sql, int index) {
  if (index < 0 || index >= sql.length) {
    return true;
  }
  return !sqlIdentifierPartChar(sql, index);
}

bool sqlIsKeywordAt(String lowerSql, String keyword, int index) {
  if (index < 0) {
    return false;
  }
  final end = index + keyword.length;
  if (end > lowerSql.length || !lowerSql.startsWith(keyword, index)) {
    return false;
  }
  return sqlIsWordBoundary(lowerSql, index - 1) &&
      sqlIsWordBoundary(lowerSql, end);
}

int findSqlKeyword(String lowerSql, String keyword, int start) {
  var index = start;
  while (index < lowerSql.length) {
    final candidate = lowerSql.indexOf(keyword, index);
    if (candidate < 0) {
      return -1;
    }
    if (sqlIsKeywordAt(lowerSql, keyword, candidate)) {
      return candidate;
    }
    index = candidate + 1;
  }
  return -1;
}
