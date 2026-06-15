/// Replaces or appends the database key in ODBC connection strings.
class OdbcConnectionStringDatabaseOverride {
  OdbcConnectionStringDatabaseOverride._();

  static final List<RegExp> _databaseKeyPatterns = [
    RegExp(r'(database)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(dbn)\s*=\s*[^;]*', caseSensitive: false),
    RegExp(r'(initial\s+catalog)\s*=\s*[^;]*', caseSensitive: false),
  ];

  static String override(String connectionString, String database) {
    var updated = connectionString;

    var replaced = false;
    for (final pattern in _databaseKeyPatterns) {
      if (pattern.hasMatch(updated)) {
        updated = updated.replaceAllMapped(pattern, (match) {
          replaced = true;
          return '${match.group(1)}=$database';
        });
      }
    }

    if (replaced) {
      return updated;
    }

    final suffix = updated.endsWith(';') ? '' : ';';
    return '$updated${suffix}DATABASE=$database';
  }
}
