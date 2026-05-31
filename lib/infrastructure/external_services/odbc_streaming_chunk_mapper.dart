/// Maps one ODBC row vector into the row-map shape emitted by streaming RPC.
Map<String, dynamic> mapOdbcRowToStreamingMap(
  List<String> columns,
  List<dynamic> row,
) {
  final mappedRow = <String, dynamic>{};
  for (var i = 0; i < columns.length; i++) {
    mappedRow[columns[i]] = row[i];
  }
  return mappedRow;
}
