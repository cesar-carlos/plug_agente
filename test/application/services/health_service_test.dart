import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

class _MockConnectionPoolDiagnostics extends Mock implements IConnectionPool, IConnectionPoolDiagnostics {}

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class _MockStreamingGateway extends Mock implements IStreamingDatabaseGateway, IStreamingGatewayDiagnostics {}

void main() {
  group('HealthService', () {
    test('should report persisted ODBC pool size and actual queue limits', () async {
      final settings = MockOdbcConnectionSettings(poolSize: 7);
      final metrics = MetricsCollector()
        ..recordSqlQueueWorkersEqualPool(workers: 7, poolSize: 7)
        ..recordPoolAcquireTimeout()
        ..recordQueryTimeout()
        ..recordPreparedStatementReuse()
        ..recordPreparedPrepareTime(const Duration(milliseconds: 12))
        ..recordDirectConnectionFallback()
        ..recordOdbcNativePoolFallback();
      final poolMock = _MockConnectionPool();
      when(poolMock.getActiveCount).thenAnswer((_) => Future.value(const Success(2)));
      final queue = SqlExecutionQueue(
        maxQueueSize: 11,
        maxConcurrentWorkers: 7,
        metricsCollector: metrics,
        defaultEnqueueTimeout: const Duration(seconds: 4),
      );
      final gateway = QueuedDatabaseGateway(
        delegate: _MockDatabaseGateway(),
        queue: queue,
      );
      final service = HealthService(
        metricsCollector: metrics,
        gateway: gateway,
        odbcSettings: settings,
        connectionPool: poolMock,
      );

      final status = await service.getHealthStatusAsync();
      final pool = status['pool']! as Map<String, Object?>;
      final sqlQueue = status['sql_queue']! as Map<String, Object?>;
      final prepared = status['prepared']! as Map<String, Object?>;
      final timeouts = status['timeouts']! as Map<String, Object?>;
      final directConnections = status['direct_connections']! as Map<String, Object?>;
      final streaming = status['streaming']! as Map<String, Object?>;

      expect(pool['size'], 7);
      expect(pool['active_count'], 2);
      expect(pool['acquire_timeout_seconds'], 30);
      expect(pool['native_pool_exposed'], isFalse);
      expect(pool['strategy'], 'lease');
      expect(pool['native_circuit_open'], isFalse);
      expect(pool['native_circuit_failures'], 0);
      expect(pool['fallbacks_total'], 2);
      expect(sqlQueue['enabled'], isTrue);
      expect(sqlQueue['max_size'], 11);
      expect(sqlQueue['max_workers'], 7);
      expect(sqlQueue['enqueue_timeout_seconds'], 4);
      expect(sqlQueue['workers_equal_pool_total'], 1);
      expect(sqlQueue['pool_wait_timeouts_total'], 1);
      expect(prepared['reuse_total'], 1);
      expect(prepared['prepare_avg_ms'], 12.0);
      expect(timeouts['sql_total'], 1);
      expect(timeouts['pool_total'], 1);
      expect(directConnections['active_count'], 0);
      expect(streaming['active_streams'], 0);
    });

    test('should cache resolved driver type and prefer pool diagnostics metadata', () async {
      final configRepository = _MockAgentConfigRepository();
      final pool = _MockConnectionPoolDiagnostics();
      when(pool.getActiveCount).thenAnswer((_) async => const Success(1));
      when(pool.getHealthDiagnostics).thenReturn(
        const {
          'strategy': 'adaptive_experimental',
          'effective_strategy': 'native',
          'native_pool_exposed': true,
          'experimental_enabled': true,
          'native_eligible': true,
        },
      );
      when(configRepository.getCurrentConfig).thenAnswer(
        (_) async => Success(
          Config(
            id: 'cfg-1',
            driverName: 'SQL Server',
            odbcDriverName: 'ODBC Driver 17 for SQL Server',
            connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=.;DATABASE=db;',
            username: 'sa',
            databaseName: 'db',
            host: 'localhost',
            port: 1433,
            createdAt: DateTime(2024),
            updatedAt: DateTime(2024),
          ),
        ),
      );

      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        connectionPool: pool,
        configRepository: configRepository,
      );

      final first = await service.getHealthStatusAsync();
      final second = await service.getHealthStatusAsync();

      final poolHealth = first['pool']! as Map<String, Object?>;
      expect(poolHealth['strategy'], 'adaptive_experimental');
      expect(poolHealth['effective_strategy'], 'native');
      expect(poolHealth['driver_type'], 'sqlServer');
      expect(poolHealth['experimental_enabled'], isTrue);
      expect(poolHealth['native_eligible'], isTrue);
      expect(second['pool'], equals(first['pool']));
      verify(pool.getActiveCount).called(1);
      verify(pool.getHealthDiagnostics).called(1);
      verify(configRepository.getCurrentConfig).called(1);
    });

    test('should expose streaming and direct connection diagnostics', () async {
      final metrics = MetricsCollector();
      final directLimiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 2,
        acquireTimeout: const Duration(milliseconds: 50),
        metricsCollector: metrics,
      );
      final streamingGateway = _MockStreamingGateway();
      final featureFlags = FeatureFlags(InMemoryAppSettingsStore());
      await featureFlags.setEnableSocketStreamingChunks(true);
      when(streamingGateway.getStreamingDiagnostics).thenReturn(
        const {
          'enabled': true,
          'active_streams': 2,
        },
      );
      when(() => streamingGateway.hasActiveStream).thenReturn(true);
      final lease = (await directLimiter.acquire(operation: 'test')).getOrThrow();
      final service = HealthService(
        metricsCollector: metrics,
        gateway: _MockDatabaseGateway(),
        streamingGateway: streamingGateway,
        directConnectionLimiter: directLimiter,
        featureFlags: featureFlags,
      );

      final status = service.getHealthStatus();

      final streaming = status['streaming']! as Map<String, Object?>;
      final directConnections = status['direct_connections']! as Map<String, Object?>;
      expect(streaming['enabled'], isTrue);
      expect(streaming['gateway_available'], isTrue);
      expect(streaming['db_streaming_flag_enabled'], isTrue);
      expect(streaming['chunk_streaming_flag_enabled'], isTrue);
      expect(streaming['active_streams'], 2);
      expect(directConnections['active_count'], 1);
      expect(directConnections['max_concurrent'], 2);
      expect(directConnections['opened_total'], 1);

      lease.release();
    });

    test('should report DB streaming auto policy when socket chunking flag is disabled', () {
      final streamingGateway = _MockStreamingGateway();
      when(streamingGateway.getStreamingDiagnostics).thenReturn(
        const {
          'enabled': true,
          'active_streams': 0,
        },
      );
      final service = HealthService(
        metricsCollector: MetricsCollector(),
        gateway: _MockDatabaseGateway(),
        streamingGateway: streamingGateway,
        featureFlags: FeatureFlags(InMemoryAppSettingsStore()),
      );

      final status = service.getHealthStatus();

      final streaming = status['streaming']! as Map<String, Object?>;
      expect(streaming['enabled'], isTrue);
      expect(streaming['gateway_available'], isTrue);
      expect(streaming['db_streaming_flag_enabled'], isTrue);
      expect(streaming['chunk_streaming_flag_enabled'], isFalse);
      expect(streaming['auto_db_streaming_policy_enabled'], isTrue);
    });

    test('should expose recent diagnostic reasons and prepared cache counters', () {
      final metrics = MetricsCollector()
        ..recordPreparedStatementReuse()
        ..recordPreparedStatementCacheMiss()
        ..recordSqlExecutionTime(const Duration(milliseconds: 20), mode: 'pooled')
        ..recordSqlExecutionTime(const Duration(milliseconds: 8), mode: 'native_compatible')
        ..recordDiagnosticReason(category: 'pool', reason: 'native_fallback')
        ..recordDiagnosticReason(category: 'pool', reason: 'native_fallback')
        ..recordDiagnosticReason(category: 'timeout', reason: 'query_timeout');
      final service = HealthService(
        metricsCollector: metrics,
        gateway: _MockDatabaseGateway(),
      );

      final status = service.getHealthStatus();

      final prepared = status['prepared']! as Map<String, Object?>;
      expect(prepared['cache_hit_total'], 1);
      expect(prepared['cache_miss_total'], 1);
      final diagnostics = status['diagnostics']! as Map<String, Object?>;
      final topReasons = diagnostics['top_recent_reasons']! as Map<String, int>;
      expect(topReasons['pool:native_fallback'], 2);
      expect(topReasons['timeout:query_timeout'], 1);
      final byMode = status['sql_execution_by_mode']! as Map<String, Object>;
      expect(byMode.keys, containsAll(['pooled', 'native_compatible']));
    });
  });
}
