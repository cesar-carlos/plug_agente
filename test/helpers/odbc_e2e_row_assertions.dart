// ODBC E2E helpers: column names from drivers vary in casing.

String? e2eRowStringForColumnInsensitive(
  Map<String, dynamic> row,
  String columnAsciiLowercase,
) {
  for (final e in row.entries) {
    if (e.key.toLowerCase() == columnAsciiLowercase) {
      return e.value?.toString();
    }
  }
  return null;
}

num? e2eFirstNumericForKeyContaining(
  Map<String, dynamic> row,
  String keySubstringAsciiLowercase,
) {
  final needle = keySubstringAsciiLowercase.toLowerCase();
  for (final e in row.entries) {
    if (e.key.toLowerCase().contains(needle)) {
      final v = e.value;
      if (v is num) {
        return v;
      }
      return num.tryParse('$v');
    }
  }
  return null;
}
