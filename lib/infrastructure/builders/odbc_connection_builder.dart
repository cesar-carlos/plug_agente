import 'package:odbc_fast/odbc_fast.dart';

import 'package:plug_agente/core/constants/sql_anywhere_connection_string.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';

/// Builds connection strings using odbc_fast's fluent builders.
///
/// Supports SQL Server, PostgreSQL, and SQL Anywhere (Sybase).
class OdbcConnectionBuilder {
  /// Builds a connection string from a [DatabaseConfig].
  ///
  /// Uses the appropriate builder for each database type:
  /// - SQL Server: SqlServerBuilder
  /// - PostgreSQL: PostgreSqlBuilder
  /// - SQL Anywhere: Manual string (no builder available)
  static String build(DatabaseConfig config) {
    switch (config.databaseType) {
      case DatabaseType.sqlServer:
        return _buildSqlServer(config);

      case DatabaseType.postgresql:
        return _buildPostgres(config);

      case DatabaseType.sybaseAnywhere:
        return _buildSybaseAnywhere(config);
    }
  }

  static String _buildSqlServer(DatabaseConfig config) {
    final builder = SqlServerBuilder()
      ..server(config.server)
      ..port(config.port)
      ..database(config.database)
      ..credentials(config.username, config.password);

    return builder.build();
  }

  static String _buildPostgres(DatabaseConfig config) {
    final builder = PostgreSqlBuilder()
      ..server(config.server)
      ..port(config.port)
      ..database(config.database)
      ..credentials(config.username, config.password);

    return builder.build();
  }

  static String _buildSybaseAnywhere(DatabaseConfig config) {
    return SqlAnywhereConnectionString.build(
      driverName: config.driverName,
      username: config.username,
      database: config.database,
      host: config.server,
      port: config.port,
      password: config.password,
    );
  }
}
