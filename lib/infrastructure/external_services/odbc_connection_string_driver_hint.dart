/// Lightweight driver-family hints from ODBC connection strings.
bool connectionStringLooksLikeSqlAnywhere(String connectionString) {
  final normalized = connectionString.toLowerCase();
  return normalized.contains('sql anywhere') ||
      normalized.contains('sybase') ||
      normalized.contains('dbeng') ||
      normalized.contains('dbf=');
}

bool connectionStringLooksLikeSqlServer(String connectionString) {
  final normalized = connectionString.toLowerCase();
  return normalized.contains('sql server') ||
      normalized.contains('odbc driver 1') ||
      normalized.contains('odbc driver 17') ||
      normalized.contains('odbc driver 18') ||
      normalized.contains('mssql') ||
      normalized.contains('driver={sql server}');
}

bool connectionStringLooksLikePostgreSQL(String connectionString) {
  final normalized = connectionString.toLowerCase();
  return normalized.contains('postgresql') || normalized.contains('postgres') || normalized.contains('psqlodbc');
}

/// Text-heavy ODBC drivers that benefit from deferred string materialization.
bool connectionStringBenefitsFromLazyStrings(String connectionString) {
  return connectionStringLooksLikeSqlAnywhere(connectionString) ||
      connectionStringLooksLikeSqlServer(connectionString) ||
      connectionStringLooksLikePostgreSQL(connectionString);
}

/// Drivers whose columnar decode path is unreliable and should use row-major
/// streaming with lazy string materialization instead.
///
/// Streaming session reuse stays off for these families: odbc_fast 4.5.1
/// CHANGELOG / PERFORMANCE.md do not document SQL Anywhere or SQL Server
/// connect reuse as safe after a finished stream.
bool connectionStringPrefersRowMajorStreaming(String connectionString) {
  return connectionStringLooksLikeSqlAnywhere(connectionString) || connectionStringLooksLikeSqlServer(connectionString);
}
