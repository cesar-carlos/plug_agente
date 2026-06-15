import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/odbc_circuit_breaker_reset_service.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_circuit_breaker.dart';

class _RecordingCircuitBreaker implements IOdbcConnectionCircuitBreaker {
  final List<String> resetCalls = [];

  @override
  void resetCircuitBreaker(String connectionString) {
    resetCalls.add(connectionString);
  }
}

void main() {
  group('OdbcCircuitBreakerResetService', () {
    late ConfigService configService;
    late _RecordingCircuitBreaker databaseGateway;
    late _RecordingCircuitBreaker streamingGateway;
    late OdbcCircuitBreakerResetService service;

    final config = Config(
      id: 'cfg-1',
      agentId: 'agent-1',
      driverName: 'SQL Server',
      odbcDriverName: 'ODBC Driver 17 for SQL Server',
      connectionString: '',
      username: 'sa',
      password: 'secret',
      databaseName: 'demo',
      host: 'localhost',
      port: 1433,
      createdAt: DateTime.utc(2025),
      updatedAt: DateTime.utc(2025),
    );

    setUp(() {
      configService = ConfigService(ConfigValidator());
      databaseGateway = _RecordingCircuitBreaker();
      streamingGateway = _RecordingCircuitBreaker();
      service = OdbcCircuitBreakerResetService(
        configService,
        databaseGateway,
        streamingGateway,
      );
    });

    test('resets runtime and persisted connection strings on both gateways', () {
      service.resetForConfig(config);

      final runtime = configService.generateConnectionString(config);
      final persisted = configService.generateConnectionStringForPersistence(config);

      expect(databaseGateway.resetCalls, [runtime, persisted]);
      expect(streamingGateway.resetCalls, [runtime, persisted]);
    });
  });
}
