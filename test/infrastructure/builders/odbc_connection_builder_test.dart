import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/builders/odbc_connection_builder.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';

void main() {
  group('OdbcConnectionBuilder', () {
    group('SQL Anywhere', () {
      test('builds connection string with HOST as host:port format', () {
        final config = DatabaseConfig.sybaseAnywhere(
          driverName: 'SQL Anywhere 16',
          username: 'dba',
          password: 'sql',
          database: 'VL',
          server: 'localhost',
          port: 2650,
        );

        final result = OdbcConnectionBuilder.build(config);

        expect(result, contains('DRIVER={SQL Anywhere 16}'));
        expect(result, contains('UID=dba'));
        expect(result, contains('PWD=sql'));
        expect(result, contains('DBN=VL'));
        expect(result, contains('HOST=localhost:2650'));
      });

      test('builds valid connection string for SQL Anywhere 17', () {
        final config = DatabaseConfig.sybaseAnywhere(
          driverName: 'SQL Anywhere 17',
          username: 'admin',
          password: 'secret',
          database: 'testdb',
          server: '192.168.1.10',
          port: 2638,
        );

        final result = OdbcConnectionBuilder.build(config);

        expect(result, contains('DRIVER={SQL Anywhere 17}'));
        expect(result, contains('HOST=192.168.1.10:2638'));
      });
    });

    group('SQL Server', () {
      test('builds connection string with server and port', () {
        final config = DatabaseConfig.sqlServer(
          driverName: 'ODBC Driver 17 for SQL Server',
          username: 'sa',
          password: 'pwd',
          database: 'master',
          server: 'localhost',
          port: 1433,
        );

        final result = OdbcConnectionBuilder.build(config);

        expect(result, isNotEmpty);
        expect(result, contains('localhost'));
        expect(result, contains('1433'));
        expect(result, contains('master'));
      });
    });

    group('PostgreSQL', () {
      test('builds connection string with server and port', () {
        final config = DatabaseConfig.postgresql(
          driverName: 'PostgreSQL Unicode',
          username: 'postgres',
          password: 'pwd',
          database: 'mydb',
          server: 'localhost',
          port: 5432,
        );

        final result = OdbcConnectionBuilder.build(config);

        expect(result, isNotEmpty);
        expect(result, contains('localhost'));
        expect(result, contains('5432'));
        expect(result, contains('mydb'));
      });
    });
  });
}
