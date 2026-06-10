import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

void main() {
  late ConfigValidator validator;

  final now = DateTime.utc(2025);

  setUp(() {
    validator = ConfigValidator();
  });

  Config buildConfig({
    String connectionString = '',
    String? password,
  }) {
    return Config(
      id: 'cfg-1',
      driverName: 'SQL Server',
      odbcDriverName: 'ODBC Driver 17 for SQL Server',
      connectionString: connectionString,
      username: 'sa',
      password: password,
      databaseName: 'demo',
      host: 'localhost',
      port: 1433,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('ConfigValidator', () {
    test('validate requires non-empty connection string by default', () {
      final result = validator.validate(buildConfig());

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.ValidationFailure>());
    });

    test('validateForPersistence accepts redacted connection string without password', () {
      final result = validator.validate(
        buildConfig(
          connectionString:
              'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost,1433;DATABASE=demo;UID=sa',
        ),
        forPersistence: true,
      );

      expect(result.isSuccess(), isTrue);
    });

    test('validateForPersistence accepts structured fields when connection string is blank', () {
      final result = validator.validate(
        buildConfig(),
        forPersistence: true,
      );

      expect(result.isSuccess(), isTrue);
    });
  });
}
