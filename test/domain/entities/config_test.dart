import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/config.dart';

void main() {
  final now = DateTime.utc(2025);

  group('Config.resolveConnectionString', () {
    test('injects secure password into redacted persisted connection string', () {
      final config = Config(
        id: 'cfg-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString:
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost,1433;DATABASE=demo;UID=sa',
        username: 'sa',
        password: 'secure-secret',
        databaseName: 'demo',
        host: 'localhost',
        port: 1433,
        createdAt: now,
        updatedAt: now,
      );

      final resolved = config.resolveConnectionString();

      expect(resolved, contains('PWD=secure-secret'));
      expect(resolved, contains('SERVER=localhost,1433'));
    });

    test('keeps embedded password when persisted connection string already has PWD', () {
      final config = Config(
        id: 'cfg-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString:
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa;PWD=embedded',
        username: 'sa',
        password: 'ignored',
        databaseName: 'demo',
        host: 'localhost',
        port: 1433,
        createdAt: now,
        updatedAt: now,
      );

      final resolved = config.resolveConnectionString();

      expect(resolved, contains('PWD=embedded'));
      expect(resolved, isNot(contains('PWD=ignored')));
    });

    test('builds from structured fields when persisted connection string is blank', () {
      final config = Config(
        id: 'cfg-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString: '',
        username: 'sa',
        password: 'field-secret',
        databaseName: 'demo',
        host: 'localhost',
        port: 1433,
        createdAt: now,
        updatedAt: now,
      );

      final resolved = config.resolveConnectionString();

      expect(resolved, contains('PWD=field-secret'));
      expect(resolved, contains('DATABASE=demo'));
    });
  });
}
