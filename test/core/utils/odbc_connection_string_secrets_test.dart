import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/sql_anywhere_connection_string.dart';
import 'package:plug_agente/core/utils/odbc_connection_string_secrets.dart';

void main() {
  group('OdbcConnectionStringSecrets', () {
    group('extractPasswordFromConnectionString', () {
      test('extracts PWD segment case-insensitively', () {
        expect(
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;PWD=secret',
          ),
          'secret',
        );
        expect(
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;pwd=secret',
          ),
          'secret',
        );
      });

      test('extracts PASSWORD segment', () {
        expect(
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            'DRIVER={PostgreSQL Unicode};SERVER=localhost;PASSWORD=secret',
          ),
          'secret',
        );
      });

      test('returns null when password segment is absent', () {
        expect(
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa',
          ),
          isNull,
        );
      });
    });

    group('injectPasswordIntoConnectionString', () {
      test('appends PWD when connection string has no embedded password', () {
        expect(
          OdbcConnectionStringSecrets.injectPasswordIntoConnectionString(
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa',
            'secret',
          ),
          'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa;PWD=secret',
        );
      });

      test('does not duplicate PWD when password is already embedded', () {
        const connectionString =
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa;PWD=secret';

        expect(
          OdbcConnectionStringSecrets.injectPasswordIntoConnectionString(
            connectionString,
            'other',
          ),
          connectionString,
        );
      });
    });

    group('stripPasswordFromConnectionString', () {
      test('removes PWD while preserving other segments', () {
        const connectionString =
            'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost,1433;DATABASE=db;UID=sa;PWD=secret';

        expect(
          OdbcConnectionStringSecrets.stripPasswordFromConnectionString(connectionString),
          'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost,1433;DATABASE=db;UID=sa',
        );
      });

      test('removes PASSWORD segment case-insensitively', () {
        expect(
          OdbcConnectionStringSecrets.stripPasswordFromConnectionString(
            'DRIVER={PostgreSQL Unicode};password=secret;SERVER=localhost',
          ),
          'DRIVER={PostgreSQL Unicode};SERVER=localhost',
        );
      });

      test('handles SQL Anywhere connection string format', () {
        final connectionString = SqlAnywhereConnectionString.build(
          driverName: 'SQL Anywhere 17',
          username: 'dba',
          database: 'demo',
          host: 'localhost',
          port: 2638,
          password: 'anywhere-secret',
        );

        expect(
          OdbcConnectionStringSecrets.extractPasswordFromConnectionString(connectionString),
          'anywhere-secret',
        );
        expect(
          OdbcConnectionStringSecrets.stripPasswordFromConnectionString(connectionString),
          'DRIVER={SQL Anywhere 17};UID=dba;DBN=demo;HOST=localhost:2638',
        );
      });
    });
  });
}
