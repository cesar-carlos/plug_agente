import 'package:flutter_test/flutter_test.dart';
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
