/// ODBC timeout detection from SQLSTATE and message heuristics.
class OdbcFailureMapperTimeout {
  OdbcFailureMapperTimeout._();

  static bool isTimeout(String? sqlState, String detail) {
    if (sqlState == 'HYT00' || sqlState == 'HYT01') {
      return true;
    }

    final normalized = detail.toLowerCase();
    return normalized.contains('timeout') ||
        normalized.contains('timed out') ||
        normalized.contains('hyt00') ||
        normalized.contains('hyt01');
  }
}
