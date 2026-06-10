final RegExp _sqlAuthorizationWhitespaceCollapse = RegExp(r'\s+');

/// Normalizes SQL for client-token authorization deduplication.
String sqlAuthorizationFingerprint(String sql) {
  return sql.trim().replaceAll(_sqlAuthorizationWhitespaceCollapse, ' ').toLowerCase();
}
