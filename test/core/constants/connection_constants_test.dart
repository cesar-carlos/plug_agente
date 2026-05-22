import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';

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
