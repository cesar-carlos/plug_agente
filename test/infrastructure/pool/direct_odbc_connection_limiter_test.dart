import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';

void main() {
  group('DirectOdbcConnectionLimiter', () {
    test('should reconfigure max concurrency without dropping active leases', () async {
      final limiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 1,
        acquireTimeout: const Duration(milliseconds: 40),
      );
      final firstLease = (await limiter.acquire(operation: 'first')).getOrThrow();

      limiter.reconfigureMaxConcurrent(2);
      final secondLease = (await limiter.acquire(operation: 'second')).getOrThrow();

      expect(limiter.maxConcurrent, 2);
      expect(limiter.activeCount, 2);

      firstLease.release();
      secondLease.release();
      expect(limiter.activeCount, 0);
    });

    test('should partition leases by operation class while preserving global budget', () async {
      final limiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 2,
        acquireTimeout: const Duration(milliseconds: 40),
      );

      final streamingLease = (await limiter.acquire(operation: 'streaming_query')).getOrThrow();
      final bulkLease = (await limiter.acquire(operation: 'bulk_insert_direct')).getOrThrow();

      expect(limiter.activeCount, 2);
      expect(limiter.isClassSaturated(DirectOdbcOperationClass.streaming), isTrue);
      expect(limiter.isClassSaturated(DirectOdbcOperationClass.bulk), isTrue);

      final third = await limiter.acquire(operation: 'batch_transaction');
      expect(third.isError(), isTrue);

      streamingLease.release();
      bulkLease.release();
      expect(limiter.activeCount, 0);
    });

    test('should expose per-operation-class diagnostics for health', () async {
      final limiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 2,
        acquireTimeout: const Duration(milliseconds: 40),
      );
      final lease = (await limiter.acquire(operation: 'streaming_query')).getOrThrow();

      final diagnostics = limiter.getOperationClassDiagnostics();
      expect(diagnostics['streaming'], isA<Map<String, Object?>>());
      expect((diagnostics['streaming']! as Map<String, Object?>)['active_count'], 1);
      expect((diagnostics['streaming']! as Map<String, Object?>)['is_saturated'], isTrue);

      lease.release();
    });

    test('should record direct connection wait time for health metrics', () async {
      final metrics = MetricsCollector();
      final limiter = DirectOdbcConnectionLimiter(
        maxConcurrent: 1,
        acquireTimeout: const Duration(milliseconds: 40),
        metricsCollector: metrics,
      );

      final lease = (await limiter.acquire(operation: 'metrics')).getOrThrow();
      lease.release();

      final snapshot = metrics.getSnapshot();
      expect(snapshot['direct_connection_wait_avg_time_ms'], isA<double>());
      expect(snapshot['direct_connection_wait_p95_time_ms'], isA<int>());
    });
  });
}
