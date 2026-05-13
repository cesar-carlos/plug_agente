import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

import '../../helpers/mock_odbc_connection_settings.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockConnectionPool extends Mock implements IConnectionPool {}

void main() {
  group('HealthService', () {
    test('should report persisted ODBC pool size and actual queue limits', () async {
      final settings = MockOdbcConnectionSettings(poolSize: 7);
      final metrics = MetricsCollector()
        ..recordSqlQueueWorkersEqualPool(workers: 7, poolSize: 7)
        ..recordPoolAcquireTimeout();
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

      expect(pool['size'], 7);
      expect(pool['active_count'], 2);
      expect(pool['acquire_timeout_seconds'], 30);
      expect(pool['native_pool_exposed'], isFalse);
      expect(sqlQueue['enabled'], isTrue);
      expect(sqlQueue['max_size'], 11);
      expect(sqlQueue['max_workers'], 7);
      expect(sqlQueue['enqueue_timeout_seconds'], 4);
      expect(sqlQueue['workers_equal_pool_total'], 1);
      expect(sqlQueue['pool_wait_timeouts_total'], 1);
    });
  });
}
