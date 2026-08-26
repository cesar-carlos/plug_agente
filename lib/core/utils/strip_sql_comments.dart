import 'package:plug_agente/core/utils/sql_text_scanner.dart';

/// Removes top-level `--` and `/* */` comments, preserving content inside
/// `'...'`, `"..."`, and `[...]` with the same quoting rules as
/// `splitSqlStatements`.
///
/// Comments are replaced with a single space so adjacent tokens are not glued
/// together (`SELECT/*x*/FROM` becomes `SELECT FROM`).
String stripTopLevelSqlComments(String sql) {
  final buffer = StringBuffer();
  scanSqlText(
    sql,
    onCode: (start, end) => buffer.write(sql.substring(start, end)),
    onLiteral: (start, end) => buffer.write(sql.substring(start, end)),
    onComment: (_, _, {required isBlock}) => buffer.write(' '),
  );
  return buffer.toString();
}
