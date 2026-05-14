import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class MockOdbcService extends Mock implements OdbcService {}

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockConnectionPool extends Mock implements IConnectionPool {}

const _asyncWorkerStats = AsyncWorkerStats(
  index: 0,
  activeRequests: 1,
  pendingRequests: 2,
  totalRouted: 10,
  completedRequests: 7,
  failedRequests: 2,
  timeouts: 1,
  fallbacksToBlocking: 1,
  cancelAttempts: 0,
  cancelSucceeded: 0,
  cancelUnsupported: 0,
  latencyAvgMicros: 100,
  latencyP95Micros: 250,
  latencyMaxMicros: 400,
  queueWaitAvgMicros: 10,
  queueWaitP95Micros: 20,
  queueWaitMaxMicros: 30,
  executionAvgMicros: 90,
  executionP95Micros: 230,
  executionMaxMicros: 370,
);

const _asyncWorkerPoolStats = AsyncWorkerPoolStats(
  workerCount: 2,
  activeRequests: 1,
  pendingRequests: 2,
  totalRouted: 10,
  completedRequests: 7,
  failedRequests: 2,
  timeouts: 1,
  fallbacksToBlocking: 1,
  cancelAttempts: 0,
  cancelSucceeded: 0,
  cancelUnsupported: 0,
  latencyAvgMicros: 100,
  latencyP95Micros: 250,
  latencyMaxMicros: 400,
  queueWaitAvgMicros: 10,
  queueWaitP95Micros: 20,
  queueWaitMaxMicros: 30,
  executionAvgMicros: 90,
  executionP95Micros: 230,
  executionMaxMicros: 370,
  workers: <AsyncWorkerStats>[_asyncWorkerStats],
);

void main() {
  group('OdbcNativeMetricsService', () {
    late MockOdbcService mockService;
    late MockAgentConfigRepository mockConfigRepository;
    late MetricsCollector metricsCollector;
    late OdbcRuntimeTuning runtimeTuning;
    late OdbcNativeMetricsService service;

    setUp(() {
      mockService = MockOdbcService();
      mockConfigRepository = MockAgentConfigRepository();
      metricsCollector = MetricsCollector()..recordQueueAdded(3);
      runtimeTuning = const OdbcRuntimeTuning(
        poolSize: 4,
        processorCount: 8,
        asyncWorkerCount: 2,
        asyncMaxPendingRequests: 16,
        asyncBackpressureMode: 'failFast',
      );
      service = OdbcNativeMetricsService(
        mockService,
        configRepository: mockConfigRepository,
        settings: MockOdbcConnectionSettings(),
        runtimeTuning: runtimeTuning,
        metricsCollector: metricsCollector,
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
      when(() => mockService.getAsyncWorkerPoolStats()).thenAnswer(
        (_) async => const Success(_asyncWorkerPoolStats),
      );

      final result = await service.collectSnapshot();

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      expect(snapshot['engine'], isA<Map<String, dynamic>>());
      expect(snapshot['prepared_statements'], isA<Map<String, dynamic>>());
      expect(snapshot['connection'], isA<Map<String, dynamic>>());
      expect(snapshot['driver_capabilities'], isA<Map<String, dynamic>>());
      expect(snapshot['app_pool'], isA<Map<String, dynamic>>());
      expect(snapshot['async_worker_pool'], isA<Map<String, dynamic>>());
      expect(snapshot['runtime_tuning'], isA<Map<String, Object>>());
      expect(snapshot['sql_queue'], isA<Map<String, dynamic>>());
      final engine = snapshot['engine'] as Map<String, dynamic>;
      final prepared = snapshot['prepared_statements'] as Map<String, dynamic>;
      final connection = snapshot['connection'] as Map<String, dynamic>;
      final capabilities = snapshot['driver_capabilities'] as Map<String, dynamic>;
      final asyncWorkerPool = snapshot['async_worker_pool'] as Map<String, dynamic>;
      final runtime = snapshot['runtime_tuning'] as Map<String, Object>;
      final sqlQueue = snapshot['sql_queue'] as Map<String, dynamic>;
      expect(engine['query_count'], 10);
      expect(engine['avg_latency_millis'], 42);
      expect(prepared['cache_hits'], 20);
      expect(prepared['cache_hit_rate'], closeTo(80.0, 0.0001));
      expect(connection['valid'], isTrue);
      expect(capabilities['supports_pooling'], isTrue);
      expect(asyncWorkerPool['worker_count'], 2);
      expect(asyncWorkerPool['configured_worker_count'], 2);
      expect(asyncWorkerPool['max_pending_requests'], 16);
      expect(asyncWorkerPool['pending_requests'], 2);
      expect(asyncWorkerPool['pending_saturation_percent'], 12.5);
      expect(asyncWorkerPool['near_pending_limit'], isFalse);
      expect(asyncWorkerPool['active_requests'], 1);
      expect(asyncWorkerPool['total_routed'], 10);
      expect(asyncWorkerPool['completed'], 7);
      expect(asyncWorkerPool['failed'], 2);
      expect(asyncWorkerPool['timeouts'], 1);
      expect(asyncWorkerPool['fallbacks_to_blocking'], 1);
      expect(asyncWorkerPool['workers'], isA<List<dynamic>>());
      expect(runtime['pool_size'], 4);
      expect(runtime['async_worker_count'], 2);
      expect(runtime['async_max_pending_requests'], 16);
      expect(sqlQueue['current_size'], 3);
      expect(sqlQueue['active_workers'], 0);
    });

    test('should flag async worker pool when pending requests are near configured limit', () async {
      service = OdbcNativeMetricsService(
        mockService,
        runtimeTuning: const OdbcRuntimeTuning(
          poolSize: 4,
          processorCount: 8,
          asyncWorkerCount: 2,
          asyncMaxPendingRequests: 2,
          asyncBackpressureMode: 'failFast',
        ),
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
      when(() => mockService.getAsyncWorkerPoolStats()).thenAnswer(
        (_) async => const Success(_asyncWorkerPoolStats),
      );

      final result = await service.collectSnapshot();

      expect(result.isSuccess(), isTrue);
      final snapshot = result.getOrThrow();
      final asyncWorkerPool = snapshot['async_worker_pool'] as Map<String, dynamic>;
      expect(asyncWorkerPool['pending_saturation_percent'], 100.0);
      expect(asyncWorkerPool['near_pending_limit'], isTrue);
    });

    test('should include app pool active connection count when pool is provided', () async {
      final pool = MockConnectionPool();
      service = OdbcNativeMetricsService(
        mockService,
        connectionPool: pool,
        settings: MockOdbcConnectionSettings(),
        runtimeTuning: runtimeTuning,
        metricsCollector: metricsCollector,
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
      when(() => mockService.getAsyncWorkerPoolStats()).thenAnswer(
        (_) async => const Success(_asyncWorkerPoolStats),
      );

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

      final result = await service.collectSnapshot();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<domain.ConnectionFailure>());
    });
  });
}
