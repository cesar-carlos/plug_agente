/// ODBC driver installation and configuration error detection.
class OdbcFailureMapperDriver {
  OdbcFailureMapperDriver._();

  static bool isDriverMissing(String? sqlState, String detail) {
    // 08xxx = connection/server errors (e.g. 08001 "Database server not found")
    if (sqlState != null && sqlState.startsWith('08')) {
      return false;
    }

    if (sqlState == 'IM002' || sqlState == 'IM003') {
      return true;
    }

    final normalized = detail.toLowerCase();
    // "Database server not found" = server unreachable, not driver missing
    if (normalized.contains('database server not found')) {
      return false;
    }

    return normalized.contains('data source name not found') ||
        normalized.contains('no default driver specified') ||
        (normalized.contains('driver') && normalized.contains('not found')) ||
        normalized.contains("can't open lib") ||
        normalized.contains('library not found');
  }
}
