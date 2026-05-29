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

    test('should reuse hint when only the password differs in the connection string', () {
      final cache = OdbcAdaptiveBufferCache();

      cache.rememberExpandedBuffer(
        connectionString: 'DSN=Test;UID=app;PWD=secret-one',
        sql: 'SELECT * FROM users',
        currentBufferBytes: 1024 * 1024,
        errorMessage: 'buffer too small: need 2097152 bytes',
      );

      // Same DSN/host/db, rotated password: the credential must not partition
      // the cache, so the learned buffer is still reused.
      final hint = cache.lookup(
        connectionString: 'DSN=Test;UID=app;PWD=secret-two',
        sql: 'SELECT * FROM users',
      );

      expect(hint, greaterThan(2097152));
    });

    test('should still isolate hints per database when password is redacted', () {
      final cache = OdbcAdaptiveBufferCache();

      cache.rememberExpandedBuffer(
        connectionString: 'DSN=Prod;DATABASE=sales;PWD=secret',
        sql: 'SELECT * FROM users',
        currentBufferBytes: 1024 * 1024,
        errorMessage: 'buffer too small: need 2097152 bytes',
      );

      final differentDatabase = cache.lookup(
        connectionString: 'DSN=Prod;DATABASE=hr;PWD=secret',
        sql: 'SELECT * FROM users',
      );

      expect(differentDatabase, isNull);
    });

    test('should expire hints after ttl', () async {
      final cache = OdbcAdaptiveBufferCache(
        entryTtl: const Duration(milliseconds: 10),
      );

      cache.rememberExpandedBuffer(
        connectionString: 'DSN=Test',
        sql: 'SELECT * FROM users',
        currentBufferBytes: 1024 * 1024,
        errorMessage: 'buffer too small: need 2097152 bytes',
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final hint = cache.lookup(
        connectionString: 'DSN=Test',
        sql: 'SELECT * FROM users',
      );

      expect(hint, isNull);
    });
  });
}
