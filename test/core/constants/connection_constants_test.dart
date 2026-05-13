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
  });
}
