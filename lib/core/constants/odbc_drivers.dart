class OdbcDrivers {
  static const String sqlServerNativeClient = 'SQL Server Native Client 11.0';
  static const String postgresqlUnicode = 'PostgreSQL Unicode';
  static const String sqlAnywhere16 = 'SQL Anywhere 16';
  static const String sqlAnywhere17 = 'SQL Anywhere 17';
  static const String sqlServer = 'SQL Server';

  static String getDefaultDriver(String driverName) {
    return switch (driverName) {
      'SQL Server' => sqlServerNativeClient,
      'PostgreSQL' => postgresqlUnicode,
      'SQL Anywhere' => sqlAnywhere16,
      _ => '',
    };
  }

  static bool isDefaultSuggestion(String odbcDriverName) {
    return odbcDriverName.isEmpty ||
        odbcDriverName == sqlServerNativeClient ||
        odbcDriverName == postgresqlUnicode ||
        odbcDriverName == sqlAnywhere16 ||
        odbcDriverName == sqlAnywhere17;
  }
}
