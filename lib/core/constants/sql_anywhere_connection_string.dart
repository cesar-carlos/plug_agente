import 'package:plug_agente/core/constants/odbc_drivers.dart';

/// Centralized SQL Anywhere connection string format.
///
/// SQL Anywhere ODBC expects HOST as host:port (combined), not separate params.
/// This matches the format used by dbping and dbisql.
class SqlAnywhereConnectionString {
  SqlAnywhereConnectionString._();

  /// Builds the HOST segment as host:port (required format for SQL Anywhere).
  static String formatHostPort(String host, int port) => '$host:$port';

  /// Builds a full SQL Anywhere connection string.
  static String build({
    required String driverName,
    required String username,
    required String database,
    required String host,
    required int port,
    String? password,
  }) {
    final effectiveDriver = driverName.isNotEmpty
        ? driverName
        : OdbcDrivers.sqlAnywhere16;
    final pwd = password != null ? ';PWD=$password' : '';
    return 'DRIVER={$effectiveDriver};'
        'UID=$username$pwd;'
        'DBN=$database;'
        'HOST=${formatHostPort(host, port)}';
  }
}
