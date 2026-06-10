import 'package:odbc_fast/odbc_fast.dart';

/// Shared ODBC error detail extraction and failure context assembly.
class OdbcFailureMapperContext {
  OdbcFailureMapperContext._();

  static String extractDetail(Object error) {
    if (error is OdbcError) {
      return error.message;
    }
    return error.toString();
  }

  static String? extractSqlState(Object error) {
    if (error is! OdbcError) {
      return null;
    }
    final sqlState = error.sqlState?.trim().toUpperCase();
    return (sqlState == null || sqlState.isEmpty) ? null : sqlState;
  }

  static Map<String, dynamic> buildBaseContext(
    Object error,
    String? operation,
    Map<String, dynamic> context,
  ) {
    final sqlState = extractSqlState(error);
    final nativeCode = error is OdbcError ? error.nativeCode : null;
    final category = error is OdbcError ? error.category.name : null;

    return {
      ...?(operation != null ? {'operation': operation} : null),
      'odbc_error_type': error.runtimeType.toString(),
      'odbc_message': extractDetail(error),
      ...?(sqlState != null ? {'odbc_sql_state': sqlState} : null),
      ...?(nativeCode != null ? {'odbc_native_code': nativeCode} : null),
      ...?(category != null ? {'odbc_error_category': category} : null),
      ...context,
    };
  }
}
