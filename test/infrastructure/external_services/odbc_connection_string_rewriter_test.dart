import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_connection_string_rewriter.dart';

void main() {
  late ConfigService connectionStringSource;

  setUp(() {
    connectionStringSource = ConfigService(ConfigValidator());
  });

  group('OdbcConnectionStringRewriter.overrideDatabase', () {
    test('replaces an existing DATABASE key preserving the original key name', () {
      final result = OdbcConnectionStringRewriter.overrideDatabase(
        'Driver={ODBC};Server=localhost;Database=old;UID=app',
        'reporting',
      );
      expect(result, contains('Database=reporting'));
      expect(result, isNot(contains('Database=old')));
    });

    test('replaces SQL Anywhere DBN key', () {
      final result = OdbcConnectionStringRewriter.overrideDatabase(
        'UID=dba;DBN=demo;Server=plug',
        'prod',
      );
      expect(result, contains('DBN=prod'));
      expect(result, isNot(contains('DBN=demo')));
    });

    test('replaces SQL Server Initial Catalog key', () {
      final result = OdbcConnectionStringRewriter.overrideDatabase(
        'Server=localhost;Initial Catalog=master;Integrated Security=true',
        'sales',
      );
      expect(result, contains('Initial Catalog=sales'));
      expect(result, isNot(contains('Initial Catalog=master')));
    });

    test('appends DATABASE clause when no database key is present', () {
      final result = OdbcConnectionStringRewriter.overrideDatabase(
        'Driver={ODBC};Server=localhost',
        'analytics',
      );
      expect(result, 'Driver={ODBC};Server=localhost;DATABASE=analytics');
    });

    test('does not duplicate the separator when string already ends with semicolon', () {
      final result = OdbcConnectionStringRewriter.overrideDatabase(
        'Server=localhost;',
        'analytics',
      );
      expect(result, 'Server=localhost;DATABASE=analytics');
    });

    test('is case-insensitive when matching the database key', () {
      final result = OdbcConnectionStringRewriter.overrideDatabase(
        'server=localhost;DATABASE=old',
        'new',
      );
      expect(result, contains('DATABASE=new'));
      expect(result, isNot(contains('DATABASE=old')));
    });
  });

  group('OdbcConnectionStringRewriter.resolve', () {
    test('overrides database in a persisted connection string when override is provided', () {
      final config = _config(connectionString: 'Driver={ODBC};Server=localhost;Database=base');
      final result = OdbcConnectionStringRewriter.resolve(
        config,
        _databaseConfig(),
        connectionStringSource,
        databaseOverride: 'override_db',
      );
      expect(result, contains('Database=override_db'));
    });

    test('returns the persisted connection string unchanged without override', () {
      final config = _config(connectionString: 'Driver={ODBC};Server=localhost;Database=base');
      final result = OdbcConnectionStringRewriter.resolve(
        config,
        _databaseConfig(),
        connectionStringSource,
      );
      expect(result, 'Driver={ODBC};Server=localhost;Database=base');
    });

    test('injects secure password into redacted persisted connection string', () {
      final config = _config(
        connectionString: 'Driver={ODBC};Server=localhost;Database=base;UID=app',
      ).copyWith(password: 'secure-secret');
      final result = OdbcConnectionStringRewriter.resolve(
        config,
        _databaseConfig(),
        connectionStringSource,
      );
      expect(result, contains('PWD=secure-secret'));
      expect(result, contains('Database=base'));
    });

    test('falls back to field-built connection string when persisted string is blank', () {
      // A real Config with a blank persisted string still derives a connection
      // string from its fields, so the resolved value reflects the config's
      // database name rather than being empty.
      final config = _config(connectionString: '   ');
      final result = OdbcConnectionStringRewriter.resolve(
        config,
        _databaseConfig(),
        connectionStringSource,
      );
      expect(result, contains('DATABASE=demo'));
    });

    test('trims whitespace-only override and falls back to the persisted string', () {
      final config = _config(connectionString: 'Driver={ODBC};Database=base');
      final result = OdbcConnectionStringRewriter.resolve(
        config,
        _databaseConfig(),
        connectionStringSource,
        databaseOverride: '   ',
      );
      expect(result, 'Driver={ODBC};Database=base');
    });
  });
}

Config _config({required String connectionString}) {
  final now = DateTime(2024, 2, 3);
  return Config(
    id: 'cfg-test',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: connectionString,
    username: 'app',
    databaseName: 'demo',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );
}

DatabaseConfig _databaseConfig({String database = 'demo'}) {
  return DatabaseConfig(
    driverName: 'ODBC Driver 17 for SQL Server',
    username: 'app',
    password: 'secret',
    database: database,
    server: 'localhost',
    port: 1433,
    databaseType: DatabaseType.sqlServer,
  );
}
