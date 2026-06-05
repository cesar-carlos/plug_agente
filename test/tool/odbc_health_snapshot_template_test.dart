import 'package:test/test.dart';

import '../../tool/src/odbc_health_snapshot_template.dart';

void main() {
  group('buildOdbcHealthSnapshotTemplate', () {
    test('should use defaults when env overrides are absent', () async {
      final snapshot = await buildOdbcHealthSnapshotTemplate(
        environment: const <String, String>{},
        processorCount: 8,
      );

      final runtime = snapshot['odbc_runtime_tuning']! as Map<String, Object?>;
      final pool = snapshot['pool']! as Map<String, Object?>;
      final sqlQueue = snapshot['sql_queue']! as Map<String, Object?>;
      final timeouts = snapshot['timeouts']! as Map<String, Object?>;
      final batch = snapshot['batch']! as Map<String, Object?>;

      expect(runtime['pool_size'], 4);
      expect(runtime['async_worker_count'], 4);
      expect(runtime['async_max_pending_requests'], 16);
      expect(runtime['result_encoding'], 'rowMajor');
      expect(pool['size'], 4);
      expect(sqlQueue['enabled'], isTrue);
      expect(sqlQueue['max_size'], 500);
      expect(sqlQueue['max_workers'], 4);
      expect(sqlQueue['enqueue_timeout_seconds'], 5);
      expect(timeouts['pool_total'], 0);
      expect(batch['transactional_direct_total'], 0);
      expect(batch['transactional_native_pool_total'], 0);
      expect(batch['transactional_native_pool_fallback_total'], 0);
      expect(batch['bulk_insert_recommended_total'], 0);
    });

    test('should honor env overrides for queue and async tuning', () async {
      final snapshot = await buildOdbcHealthSnapshotTemplate(
        environment: const <String, String>{
          'ODBC_POOL_SIZE': '7',
          'ODBC_ASYNC_WORKER_COUNT': '3',
          'ODBC_ASYNC_MAX_PENDING_REQUESTS': '19',
          'ODBC_RESULT_ENCODING': 'columnarCompressed',
          'SQL_QUEUE_MAX_SIZE': '13',
          'SQL_QUEUE_MAX_WORKERS': '5',
          'SQL_QUEUE_TIMEOUT_SEC': '9',
        },
        processorCount: 16,
      );

      final runtime = snapshot['odbc_runtime_tuning']! as Map<String, Object?>;
      final pool = snapshot['pool']! as Map<String, Object?>;
      final sqlQueue = snapshot['sql_queue']! as Map<String, Object?>;

      expect(runtime['pool_size'], 7);
      expect(runtime['async_worker_count'], 3);
      expect(runtime['async_max_pending_requests'], 19);
      expect(runtime['result_encoding'], 'columnarCompressed');
      expect(pool['size'], 7);
      expect(sqlQueue['max_size'], 13);
      expect(sqlQueue['max_workers'], 5);
      expect(sqlQueue['enqueue_timeout_seconds'], 9);
    });
  });
}
