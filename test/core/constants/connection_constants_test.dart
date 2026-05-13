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
  });
}
