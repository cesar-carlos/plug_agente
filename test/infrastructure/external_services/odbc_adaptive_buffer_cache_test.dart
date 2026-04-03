import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_adaptive_buffer_cache.dart';

void main() {
  group('OdbcAdaptiveBufferCache', () {
    test('should remember expanded buffer per connection string and sql', () {
      final cache = OdbcAdaptiveBufferCache();

      cache.rememberExpandedBuffer(
        connectionString: 'DSN=Test',
        sql: 'SELECT * FROM users',
        currentBufferBytes: 1024 * 1024,
        errorMessage: 'buffer too small: need 2097152 bytes',
      );

      final hint = cache.lookup(
        connectionString: 'DSN=Test',
        sql: ' SELECT  *  FROM   users ',
      );

      expect(hint, greaterThan(2097152));
    });
  });
}
