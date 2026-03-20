/// Truncates ODBC/SQL result rows to a maximum count (response_truncation policy).
List<Map<String, dynamic>> truncateSqlResultRows(
  List<Map<String, dynamic>> rows,
  int maxRows,
) {
  if (maxRows < 1 || rows.length <= maxRows) {
    return rows;
  }
  return List<Map<String, dynamic>>.from(rows.getRange(0, maxRows));
}
