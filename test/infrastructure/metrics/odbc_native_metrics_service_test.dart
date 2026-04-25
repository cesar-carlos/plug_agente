import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:result_dart/result_dart.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  group('OdbcNativeMetricsService', () {
    late MockOdbcService mockService;
    late MockAgentConfigRepository mockConfigRepository;
    late OdbcNativeMetricsService service;

    setUp(() {
      mockService = MockOdbcService();
      mockConfigRepository = MockAgentConfigRepository();
      service = OdbcNativeMetricsService(
        mockService,
        configRepository: mockConfigRepository,
      );
    });

    test('should return merged snapshot when native calls succeed', () async {
      final config = Config(
        id: 'cfg-1',
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17',
        connectionString: 'DSN=Test',
        username: 'u',
        databaseName: 'db',
        host: 'localhost',
        port: 1433,
        nome: 'Empresa Exemplo',
        nomeFantasia: 'Fantasia Exemplo',
        cnaeCnpjCpf: '52998224725',
        telefone: '1133334444',
        celular: '11988887777',
        email: 'contato@exemplo.com',
        endereco: 'Rua Central',
        numeroEndereco: '123',
        bairro: 'Centro',
        cep: '01001000',
        nomeMunicipio: 'Sao Paulo',
        ufMunicipio: 'SP',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      when(
        mockConfigRepository.getCurrentConfig,
      ).thenAnswer((_) async => Success(config));
      when(() => mockService.getMetrics()).thenAnswer(
        (_) async => const Success(
          OdbcMetrics(
            queryCount: 10,
            errorCount: 2,
            uptimeSecs: 100,
            totalLatencyMillis: 420,
            avgLatencyMillis: 42,
          ),
        ),
      );
      when(() => mockService.getPreparedStatementsMetrics()).thenAnswer(
        (_) async => const Success(
          PreparedStatementMetrics(
            cacheSize: 4,
            cacheMaxSize: 16,
            cacheHits: 20,
            cacheMisses: 5,
            totalPrepares: 8,
            totalExecutions: 80,
            memoryUsageBytes: 4096,
            avgExecutionsPerStmt: 10,
          ),
        ),
      );
      when(() => mockService.validateConnectionString('DSN=Test')).thenAnswer(
        (_) async => const Success(unit),
      );
      when(() => mockService.getDriverCapabilities('DSN=Test')).thenAnswer(
        (_) async => const Success(<String, Object?>{'supports_pooling': true}),
      );

      final result = await service.collectSnapshot();

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      expect(snapshot['engine'], isA<Map<String, dynamic>>());
      expect(snapshot['prepared_statements'], isA<Map<String, dynamic>>());
      expect(snapshot['connection'], isA<Map<String, dynamic>>());
      expect(snapshot['driver_capabilities'], isA<Map<String, dynamic>>());
      expect(snapshot['app_pool'], isA<Map<String, dynamic>>());
      final engine = snapshot['engine'] as Map<String, dynamic>;
      final prepared = snapshot['prepared_statements'] as Map<String, dynamic>;
      final connection = snapshot['connection'] as Map<String, dynamic>;
      final capabilities = snapshot['driver_capabilities'] as Map<String, dynamic>;
      expect(engine['query_count'], 10);
      expect(engine['avg_latency_millis'], 42);
      expect(prepared['cache_hits'], 20);
      expect(prepared['cache_hit_rate'], closeTo(80.0, 0.0001));
      expect(connection['valid'], isTrue);
      expect(capabilities['supports_pooling'], isTrue);
    });

    test('should include app pool active connection count when pool is provided', () async {
      final pool = MockConnectionPool();
      service = OdbcNativeMetricsService(
        mockService,
        connectionPool: pool,
      );
      when(() => mockService.getMetrics()).thenAnswer(
        (_) async => const Success(
          OdbcMetrics(
            queryCount: 1,
            errorCount: 0,
            uptimeSecs: 10,
            totalLatencyMillis: 5,
            avgLatencyMillis: 5,
          ),
        ),
      );
      when(() => mockService.getPreparedStatementsMetrics()).thenAnswer(
        (_) async => const Success(
          PreparedStatementMetrics(
            cacheSize: 0,
            cacheMaxSize: 16,
            cacheHits: 0,
            cacheMisses: 0,
            totalPrepares: 0,
            totalExecutions: 0,
            memoryUsageBytes: 0,
            avgExecutionsPerStmt: 0,
          ),
        ),
      );
      when(pool.getActiveCount).thenAnswer((_) async => const Success(3));

      final result = await service.collectSnapshot();

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      final appPool = snapshot['app_pool'] as Map<String, dynamic>;
      expect(appPool['available'], isTrue);
      expect(appPool['active_connections'], 3);
    });

    test('should return typed failure when getMetrics fails', () async {
      when(() => mockService.getMetrics()).thenAnswer(
        (_) async => const Failure(
          ConnectionError(message: 'native metrics failed'),
        ),
      );

      final result = await service.collectSnapshot();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
      verifyNever(() => mockService.getPreparedStatementsMetrics());
    });
  });
}
