import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_circuit_breaker_reset.dart';
import 'package:result_dart/result_dart.dart';

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class FakeConfig extends Fake implements Config {}

class _RecordingCircuitBreakerReset implements IOdbcCircuitBreakerReset {
  final List<Config> resetCalls = [];

  @override
  void resetForConfig(Config config) {
    resetCalls.add(config);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeConfig());
  });

  group('SaveAgentConfig circuit breaker', () {
    late MockAgentConfigRepository repository;
    late ConfigService configService;
    late _RecordingCircuitBreakerReset circuitBreakerReset;
    late SaveAgentConfig useCase;

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
      repository = MockAgentConfigRepository();
      configService = ConfigService(ConfigValidator());
      circuitBreakerReset = _RecordingCircuitBreakerReset();
      useCase = SaveAgentConfig(
        repository,
        configService,
        circuitBreakerReset: circuitBreakerReset,
      );
    });

    test('resets ODBC circuit breaker on successful save', () async {
      when(() => repository.save(any())).thenAnswer((invocation) async {
        return Success(invocation.positionalArguments.first as Config);
      });

      final result = await useCase.call(config);

      expect(result.isSuccess(), isTrue);
      expect(circuitBreakerReset.resetCalls, [config]);
    });
  });
}
