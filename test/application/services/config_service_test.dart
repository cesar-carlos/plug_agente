import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';

void main() {
  late ConfigService service;

  final now = DateTime.utc(2025);
  final baseConfig = Config(
    id: 'cfg-1',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: '',
    username: 'sa',
    password: 'runtime-secret',
    databaseName: 'demo',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() {
    service = ConfigService(ConfigValidator());
  });

  group('ConfigService', () {
    test('generateConnectionString includes PWD for runtime use', () {
      final connectionString = service.generateConnectionString(baseConfig);

      expect(connectionString, contains('PWD=runtime-secret'));
      expect(connectionString, contains('SERVER=localhost,1433'));
    });

    test('generateConnectionStringForPersistence never embeds PWD', () {
      final runtime = service.generateConnectionString(baseConfig);
      final persisted = service.generateConnectionStringForPersistence(baseConfig);

      expect(runtime, contains('PWD=runtime-secret'));
      expect(persisted, isNot(contains('PWD=')));
      expect(persisted, contains('SERVER=localhost,1433'));
    });
  });
}
