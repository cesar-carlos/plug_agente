import 'package:dart_odbc/dart_odbc.dart';
import '../../config/database_type.dart';

class MyOdbc {
  late final DartOdbc driver;
  final String driverName;
  final String username;
  final String password;
  final String database;
  final String server;
  final int port;
  final DatabaseType databaseType;

  MyOdbc({
    required this.driverName,
    required this.username,
    required this.password,
    required this.database,
    required this.server,
    required this.port,
    DatabaseType? databaseType,
  }) : databaseType = databaseType ?? DatabaseType.sqlServer {
    driver = DartOdbc();
  }

  String getConnectionString() {
    switch (databaseType) {
      case DatabaseType.sqlServer:
        return '''
      DRIVER={$driverName};
      Server=$server;
      Port=$port;
      Database=$database;
      UID=$username;
      PWD=$password;
      Trusted_connection = yes;
      MARS_Connection = yes;
      MultipleActiveResultSets = true;
      Packet Size = 4096;
      TrustServerCertificate = yes;
      Encrypt = false;
      Connection Timeout = 30;
      ReadOnly = 0;
    ''';
      case DatabaseType.sybaseAnywhere:
        return '''
      DRIVER={$driverName};
      ServerName=$server;
      Port=$port;
      DatabaseName=$database;
      UID=$username;
      PWD=$password;
      Connection Timeout = 30;
    ''';
      case DatabaseType.postgresql:
        return '''
      DRIVER={$driverName};
      Server=$server;
      Port=$port;
      Database=$database;
      UID=$username;
      PWD=$password;
      Connection Timeout = 30;
    ''';
    }
  }

  DatabaseType get type => databaseType;

  Future<void> connect() async {
    try {
      await driver.connectWithConnectionString(getConnectionString());
    } catch (err) {
      throw Exception('Erro ao conectar com o banco de dados: $err');
    }
  }

  Future<List<Map<String, dynamic>>> execute(String query) async {
    try {
      final result = await driver.execute(query);
      return result;
    } catch (err) {
      throw Exception('Erro ao executar a query: $err');
    }
  }

  Future<void> disconnect() async {
    await driver.disconnect();
  }

  Future<void> startTransaction() async {
    try {
      String transactionCommand;
      switch (databaseType) {
        case DatabaseType.sqlServer:
        case DatabaseType.sybaseAnywhere:
          transactionCommand = 'BEGIN TRANSACTION';
          break;
        case DatabaseType.postgresql:
          transactionCommand = 'BEGIN';
          break;
      }
      await driver.execute(transactionCommand);
    } catch (err) {
      throw Exception('Erro ao iniciar transação: $err');
    }
  }

  Future<void> commitTransaction() async {
    try {
      await driver.execute('COMMIT');
    } catch (err) {
      throw Exception('Erro ao fazer commit: $err');
    }
  }

  Future<void> rollbackTransaction() async {
    try {
      await driver.execute('ROLLBACK');
    } catch (err) {
      throw Exception('Erro ao fazer rollback: $err');
    }
  }
}
