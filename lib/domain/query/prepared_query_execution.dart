/// SQL and parameters ready for ODBC execution after optional preparation.
class OdbcPreparedQueryExecution {
  const OdbcPreparedQueryExecution({
    required this.sql,
    required this.parameters,
  });

  final String sql;
  final Map<String, dynamic>? parameters;
}
