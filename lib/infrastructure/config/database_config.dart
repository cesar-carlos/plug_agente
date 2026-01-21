import 'database_type.dart';

class DatabaseConfig {
  final String driverName;
  final String username;
  final String password;
  final String database;
  final String server;
  final int port;
  final DatabaseType databaseType;

  DatabaseConfig({
    required this.driverName,
    required this.username,
    required this.password,
    required this.database,
    required this.server,
    required this.port,
    DatabaseType? databaseType,
  }) : databaseType = databaseType ?? DatabaseType.sqlServer;

  factory DatabaseConfig.sqlServer({
    required String driverName,
    required String username,
    required String password,
    required String database,
    required String server,
    required int port,
  }) {
    return DatabaseConfig(
      driverName: driverName,
      username: username,
      password: password,
      database: database,
      server: server,
      port: port,
      databaseType: DatabaseType.sqlServer,
    );
  }

  factory DatabaseConfig.sybaseAnywhere({
    required String driverName,
    required String username,
    required String password,
    required String database,
    required String server,
    required int port,
  }) {
    return DatabaseConfig(
      driverName: driverName,
      username: username,
      password: password,
      database: database,
      server: server,
      port: port,
      databaseType: DatabaseType.sybaseAnywhere,
    );
  }

  factory DatabaseConfig.postgresql({
    required String driverName,
    required String username,
    required String password,
    required String database,
    required String server,
    required int port,
  }) {
    return DatabaseConfig(
      driverName: driverName,
      username: username,
      password: password,
      database: database,
      server: server,
      port: port,
      databaseType: DatabaseType.postgresql,
    );
  }
}
