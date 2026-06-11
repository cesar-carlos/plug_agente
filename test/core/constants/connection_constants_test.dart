import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/direct_odbc_operation_class.dart';

void main() {
  group('ConnectionConstants', () {
    setUp(dotenv.clean);
    tearDown(dotenv.clean);

    test('should use persisted pool size for SQL queue workers when override is absent', () {
      expect(ConnectionConstants.sqlQueueMaxWorkersForPoolSize(7), 7);
    });

    test('should use SQL_QUEUE_MAX_WORKERS when override is valid', () {
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_WORKERS=9');

      expect(ConnectionConstants.sqlQueueMaxWorkersForPoolSize(7), 9);
    });

    test('should fall back to persisted pool size when SQL_QUEUE_MAX_WORKERS is invalid', () {
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_WORKERS=invalid');

      expect(ConnectionConstants.sqlQueueMaxWorkersForPoolSize(7), 7);
    });

    test('should fall back to default pool size when persisted pool size is invalid', () {
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_WORKERS=0');

      expect(
        ConnectionConstants.sqlQueueMaxWorkersForPoolSize(0),
        ConnectionConstants.defaultPoolSize,
      );
    });

    test('should default hub persistent retry to unlimited', () {
      expect(ConnectionConstants.hubPersistentRetryMaxFailedTicks, 0);
    });

    test('should default ODBC async worker count to min pool size and processor count', () {
      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(8, 4),
        4,
      );
      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(2, 8),
        2,
      );
      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(0, 0),
        1,
      );
    });

    test('should use valid ODBC_ASYNC_WORKER_COUNT override', () {
      dotenv.loadFromString(envString: 'ODBC_ASYNC_WORKER_COUNT=3');

      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(8, 4),
        3,
      );
    });

    test('should cap ODBC_ASYNC_WORKER_COUNT override at pool and CPU ceiling', () {
      dotenv.loadFromString(envString: 'ODBC_ASYNC_WORKER_COUNT=9');

      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(8, 4),
        4,
      );
    });

    test('should ignore invalid ODBC_ASYNC_WORKER_COUNT override', () {
      dotenv.loadFromString(envString: 'ODBC_ASYNC_WORKER_COUNT=invalid');

      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(8, 4),
        4,
      );

      dotenv.clean();
      dotenv.loadFromString(envString: 'ODBC_ASYNC_WORKER_COUNT=0');

      expect(
        ConnectionConstants.odbcAsyncWorkerCountForPoolSize(8, 4),
        4,
      );
    });

    test('should default ODBC async max pending requests to pool size times four', () {
      expect(
        ConnectionConstants.odbcAsyncMaxPendingRequestsForPoolSize(7),
        28,
      );
      expect(
        ConnectionConstants.odbcAsyncMaxPendingRequestsForPoolSize(0),
        4,
      );
    });

    test('should use valid ODBC_ASYNC_MAX_PENDING_REQUESTS override', () {
      dotenv.loadFromString(envString: 'ODBC_ASYNC_MAX_PENDING_REQUESTS=64');

      expect(
        ConnectionConstants.odbcAsyncMaxPendingRequestsForPoolSize(7),
        64,
      );
    });

    test('should ignore invalid ODBC_ASYNC_MAX_PENDING_REQUESTS override', () {
      dotenv.loadFromString(envString: 'ODBC_ASYNC_MAX_PENDING_REQUESTS=invalid');

      expect(
        ConnectionConstants.odbcAsyncMaxPendingRequestsForPoolSize(7),
        28,
      );

      dotenv.clean();
      dotenv.loadFromString(envString: 'ODBC_ASYNC_MAX_PENDING_REQUESTS=0');

      expect(
        ConnectionConstants.odbcAsyncMaxPendingRequestsForPoolSize(7),
        28,
      );
    });

    test('should reserve half of pool for direct ODBC connections by default', () {
      expect(ConnectionConstants.directOdbcConnectionConcurrency(7), 3);
      expect(ConnectionConstants.directOdbcConnectionCapacityStrategy(), 'half_pool_reserved');
    });

    test('should align SQL queue per-kind worker caps with direct ODBC class budgets', () {
      expect(ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(8), 2);
      expect(ConnectionConstants.sqlQueueMaxLongQueryWorkersForWorkers(8), 2);
      expect(ConnectionConstants.sqlQueueMaxStreamingWorkersForWorkers(8), 2);
      expect(ConnectionConstants.sqlQueueMaxNonQueryWorkersForWorkers(8), 4);
      expect(ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(1), 1);
    });

    test('should use persisted pool size for direct ODBC budget when workers override differs', () {
      expect(
        ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(
          12,
          persistedPoolSize: 8,
        ),
        2,
      );
    });

    test('should default SQL queue max size to 16', () {
      expect(ConnectionConstants.sqlQueueMaxSize, ConnectionConstants.defaultSqlQueueMaxSize);
    });

    test('should use valid SQL_QUEUE_MAX_SIZE override', () {
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_SIZE=32');

      expect(ConnectionConstants.sqlQueueMaxSize, 32);
    });

    test('should ignore invalid SQL_QUEUE_MAX_SIZE override', () {
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_SIZE=invalid');

      expect(ConnectionConstants.sqlQueueMaxSize, ConnectionConstants.defaultSqlQueueMaxSize);

      dotenv.clean();
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_SIZE=0');

      expect(ConnectionConstants.sqlQueueMaxSize, ConnectionConstants.defaultSqlQueueMaxSize);
    });

    test('should default rpc sql.execute soft limit to queue workers plus queue depth', () {
      expect(ConnectionConstants.rpcSqlExecuteConcurrencySoftLimit, 24);
    });

    test('should default max concurrent rpc handlers from sql soft limit plus headroom', () {
      expect(
        ConnectionConstants.maxConcurrentRpcHandlers,
        ConnectionConstants.rpcSqlExecuteConcurrencySoftLimit +
            ConnectionConstants.defaultMaxConcurrentRpcHandlersHeadroom,
      );
    });

    test('should default playground streaming row cap to 10000', () {
      expect(
        ConnectionConstants.playgroundStreamingMaxResultRows,
        ConnectionConstants.defaultPlaygroundStreamingMaxResultRows,
      );
      expect(ConnectionConstants.defaultPlaygroundStreamingMaxResultRows, 10000);
    });

    test('should honor PLAYGROUND_STREAMING_MAX_RESULT_ROWS override', () {
      dotenv.loadFromString(envString: 'PLAYGROUND_STREAMING_MAX_RESULT_ROWS=25000');

      expect(ConnectionConstants.playgroundStreamingMaxResultRows, 25000);

      dotenv.clean();
    });

    test('should use SQL_QUEUE_MAX_BATCH_WORKERS override when valid', () {
      dotenv.loadFromString(envString: 'SQL_QUEUE_MAX_BATCH_WORKERS=3');

      expect(ConnectionConstants.sqlQueueMaxBatchWorkersForWorkers(8), 3);
    });

    test('should derive direct ODBC operation class caps from global budget', () {
      expect(
        ConnectionConstants.directOdbcOperationClassCap(
          DirectOdbcOperationClass.streaming,
          4,
        ),
        2,
      );
      expect(
        ConnectionConstants.directOdbcOperationClassCap(
          DirectOdbcOperationClass.bulk,
          4,
        ),
        2,
      );
      expect(
        ConnectionConstants.directOdbcOperationClassCap(
          DirectOdbcOperationClass.batchTransaction,
          2,
        ),
        1,
      );
    });

    test('should reserve half of pool for read-only batch parallelism by default', () {
      expect(ConnectionConstants.readOnlyBatchParallelismForPoolSize(7), 3);
      expect(ConnectionConstants.readOnlyBatchParallelismForPoolSize(1), 1);
      expect(ConnectionConstants.readOnlyBatchParallelismForPoolSize(0), 1);
      expect(ConnectionConstants.bulkInsertParallelismForPoolSize(8), 4);
    });

    test('should default benchmark-tuned ODBC pool and bulk insert settings', () {
      expect(ConnectionConstants.defaultPoolSize, 8);
      expect(ConnectionConstants.defaultSqlQueueMaxSize, 16);
      expect(ConnectionConstants.bulkInsertParallelEnabled, isTrue);
      expect(ConnectionConstants.nativeWarmUpEnabled, isTrue);
      expect(ConnectionConstants.bulkInsertParallelRowThreshold, 50000);
      expect(ConnectionConstants.bulkInsertChunkRowCount, 10000);
      expect(ConnectionConstants.batchBulkInsertRouteThreshold, 50);
    });

    test('should read bulk insert parallel env overrides', () {
      dotenv.loadFromString(
        envString:
            'ODBC_BULK_INSERT_PARALLEL_ROW_THRESHOLD=25000\n'
            'ODBC_BULK_INSERT_PARALLEL_ENABLED=false',
      );
      expect(ConnectionConstants.bulkInsertParallelRowThreshold, 25000);
      expect(ConnectionConstants.bulkInsertParallelEnabled, isFalse);
      dotenv.clean();
    });

    test('should read native warm-up env override', () {
      dotenv.loadFromString(envString: 'ODBC_NATIVE_WARMUP_ENABLED=false');
      expect(ConnectionConstants.nativeWarmUpEnabled, isFalse);
      dotenv.clean();
    });

    test('should use ODBC_DIRECT_CONNECTION_MAX_CONCURRENT when override is valid', () {
      dotenv.loadFromString(envString: 'ODBC_DIRECT_CONNECTION_MAX_CONCURRENT=5');

      expect(ConnectionConstants.directOdbcConnectionConcurrency(7), 5);
      expect(ConnectionConstants.directOdbcConnectionCapacityStrategy(), 'env_override');
      expect(ConnectionConstants.directOdbcConnectionOverrideExceedsPool(7), isFalse);
    });

    test('should cap direct ODBC override at pool size', () {
      dotenv.loadFromString(envString: 'ODBC_DIRECT_CONNECTION_MAX_CONCURRENT=9');

      expect(ConnectionConstants.directOdbcConnectionConcurrency(4), 4);
      expect(ConnectionConstants.directOdbcConnectionOverrideExceedsPool(4), isTrue);
    });

    test('should default gzip isolate threshold to 32 KiB', () {
      expect(
        ConnectionConstants.gzipIsolateThresholdBytes,
        ConnectionConstants.defaultGzipIsolateThresholdBytes,
      );
      expect(ConnectionConstants.defaultGzipIsolateThresholdBytes, 32 * 1024);
    });

    test('should use TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES when valid', () {
      dotenv.loadFromString(envString: 'TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES=65536');

      expect(ConnectionConstants.gzipIsolateThresholdBytes, 65536);
    });

    test('should ignore invalid TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES override', () {
      dotenv.loadFromString(envString: 'TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES=invalid');

      expect(
        ConnectionConstants.gzipIsolateThresholdBytes,
        ConnectionConstants.defaultGzipIsolateThresholdBytes,
      );

      dotenv.clean();
      dotenv.loadFromString(envString: 'TRANSPORT_GZIP_ISOLATE_THRESHOLD_BYTES=0');

      expect(
        ConnectionConstants.gzipIsolateThresholdBytes,
        ConnectionConstants.defaultGzipIsolateThresholdBytes,
      );
    });

    test('should default RPC idempotency entry TTL to 300 seconds', () {
      expect(ConnectionConstants.rpcIdempotencyEntryTtl, const Duration(seconds: 300));
    });

    test('should use RPC_IDEMPOTENCY_CACHE_TTL_SECONDS when valid', () {
      dotenv.loadFromString(envString: 'RPC_IDEMPOTENCY_CACHE_TTL_SECONDS=120');

      expect(ConnectionConstants.rpcIdempotencyEntryTtl, const Duration(seconds: 120));
    });

    test('should clamp RPC_IDEMPOTENCY_CACHE_TTL_SECONDS below minimum to 60', () {
      dotenv.loadFromString(envString: 'RPC_IDEMPOTENCY_CACHE_TTL_SECONDS=30');

      expect(ConnectionConstants.rpcIdempotencyEntryTtl, const Duration(seconds: 60));
    });

    test('should clamp RPC_IDEMPOTENCY_CACHE_TTL_SECONDS above maximum to 86400', () {
      dotenv.loadFromString(envString: 'RPC_IDEMPOTENCY_CACHE_TTL_SECONDS=200000');

      expect(ConnectionConstants.rpcIdempotencyEntryTtl, const Duration(seconds: 86400));
    });

    test('should fall back to default when RPC_IDEMPOTENCY_CACHE_TTL_SECONDS is invalid', () {
      dotenv.loadFromString(envString: 'RPC_IDEMPOTENCY_CACHE_TTL_SECONDS=not-a-number');

      expect(ConnectionConstants.rpcIdempotencyEntryTtl, const Duration(seconds: 300));
    });

    test('should default agent action RPC idempotency TTL to min execution retention and 24h', () {
      expect(ConnectionConstants.agentActionRpcIdempotencyEntryTtl, const Duration(hours: 24));
    });

    test('should use AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS when valid', () {
      dotenv.loadFromString(envString: 'AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS=7200');

      expect(ConnectionConstants.agentActionRpcIdempotencyEntryTtl, const Duration(hours: 2));
    });

    test('should clamp AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS below minimum to 60', () {
      dotenv.loadFromString(envString: 'AGENT_ACTION_RPC_IDEMPOTENCY_CACHE_TTL_SECONDS=10');

      expect(ConnectionConstants.agentActionRpcIdempotencyEntryTtl, const Duration(seconds: 60));
    });

    test('should align agent action RPC idempotency default with shorter execution retention', () {
      dotenv.loadFromString(envString: 'AGENT_ACTION_EXECUTION_RETENTION_DAYS=1');

      expect(ConnectionConstants.agentActionRpcIdempotencyEntryTtl, const Duration(days: 1));
    });
  });
}
