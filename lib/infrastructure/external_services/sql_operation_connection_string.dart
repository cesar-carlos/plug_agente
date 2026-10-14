import 'package:plug_agente/domain/errors/sql_operation_failure.dart';

/// ODBC attribute parsing preserves braced values and never edits inside a credential.
class SqlOperationConnectionString {
  const SqlOperationConnectionString._();
  static String bindDatabase(String original, String database) {
    if (database.isEmpty || database.trim() != database || RegExp(r'[;{}\r\n\x00]').hasMatch(database)) _deny();
    final attributes = <String>[];
    var start = 0;
    var braced = false;
    for (var i = 0; i < original.length; i++) {
      final char = original[i];
      if (braced && char == '}') {
        if (i + 1 < original.length && original[i + 1] == '}') {
          i++;
        } else {
          braced = false;
        }
      } else if (!braced && char == '{') {
        braced = true;
      } else if (!braced && char == ';') {
        attributes.add(original.substring(start, i));
        start = i + 1;
      }
    }
    if (braced) _deny();
    attributes.add(original.substring(start));
    var bound = false;
    final output = <String>[];
    for (final attribute in attributes) {
      if (attribute.trim().isEmpty) continue;
      final separator = attribute.indexOf('=');
      if (separator < 1) _deny();
      final key = attribute.substring(0, separator).trim();
      if ({'database', 'dbn', 'initial catalog', 'dbname', 'dbq'}.contains(key.toLowerCase())) {
        output.add('$key=$database');
        bound = true;
      } else {
        output.add(attribute);
      }
    }
    if (!bound) output.add('DATABASE=$database');
    return '${output.join(';')};';
  }

  static Never _deny() =>
      throw SqlOperationFailure(code: 'SQL_OPERATION_SOURCE_INVALID', message: 'Invalid ODBC source binding.');
}
