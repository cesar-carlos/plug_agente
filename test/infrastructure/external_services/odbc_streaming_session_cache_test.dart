import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_session_cache.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('OdbcStreamingSessionCache', () {
    test('reuses connection id within TTL for SQL Server DSN', () {
      final now = DateTime.utc(2026, 6, 16, 12);
      final cache = OdbcStreamingSessionCache(
        ttl: const Duration(seconds: 30),
        clock: () => now,
      );
      const connectionString = 'Driver={ODBC Driver 18 for SQL Server};Server=localhost;';

      expect(
        cache.offer(connectionString: connectionString, connectionId: 'conn-1'),
        isTrue,
      );
      expect(cache.tryTake(connectionString), 'conn-1');
      expect(cache.tryTake(connectionString), isNull);
    });

    test('does not reuse SQL Anywhere connections', () {
      final cache = OdbcStreamingSessionCache();
      const connectionString = 'Driver={SQL Anywhere 17};dbf=C:/data.db;';

      expect(
        cache.offer(connectionString: connectionString, connectionId: '42'),
        isFalse,
      );
      expect(cache.tryTake(connectionString), isNull);
    });

    test('expires cached sessions after TTL', () {
      var now = DateTime.utc(2026, 6, 16, 12);
      final cache = OdbcStreamingSessionCache(
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      cache.offer(connectionString: connectionString, connectionId: 'pg-1');
      now = now.add(const Duration(seconds: 6));

      expect(cache.tryTake(connectionString), isNull);
    });

    test('drainCachedSessions disconnects and clears all cached connection ids', () async {
      final disconnected = <String>[];
      final cache = OdbcStreamingSessionCache(
        disconnectConnection: (connectionId) async {
          disconnected.add(connectionId);
          return const Success(unit);
        },
      );
      const connectionString = 'Driver={ODBC Driver 18 for SQL Server};Server=localhost;';

      cache.offer(connectionString: connectionString, connectionId: 'conn-1');
      cache.offer(
        connectionString: 'Driver={PostgreSQL};Server=localhost;',
        connectionId: 'conn-2',
      );
      expect(cache.entryCount, 2);

      final drainResult = await cache.drainCachedSessions();

      expect(drainResult.isSuccess(), isTrue);
      expect(cache.entryCount, 0);
      expect(disconnected, <String>['conn-1', 'conn-2']);
    });

    test('drainCachedSessions returns typed failure when disconnect fails', () async {
      final cache = OdbcStreamingSessionCache(
        disconnectConnection: (_) async => Failure(
          domain.ConnectionFailure.withContext(
            message: 'disconnect failed',
            context: const {'reason': 'pool_error'},
          ),
        ),
      );
      const connectionString = 'Driver={ODBC Driver 18 for SQL Server};Server=localhost;';

      cache.offer(connectionString: connectionString, connectionId: 'conn-1');

      final drainResult = await cache.drainCachedSessions();

      expect(drainResult.isError(), isTrue);
      expect(drainResult.exceptionOrNull(), isA<domain.ConnectionFailure>());
      expect(cache.entryCount, 0);
    });
  });
}
