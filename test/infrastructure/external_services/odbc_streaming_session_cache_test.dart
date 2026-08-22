import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_disconnect_tracker.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_session_cache.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('OdbcStreamingSessionCache', () {
    test('reuses connection id within TTL for PostgreSQL DSN', () async {
      final now = DateTime.utc(2026, 6, 16, 12);
      final cache = OdbcStreamingSessionCache(
        ttl: const Duration(seconds: 30),
        clock: () => now,
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      expect(
        await cache.offer(connectionString: connectionString, connectionId: 'conn-1'),
        isTrue,
      );
      expect(cache.tryTake(connectionString), 'conn-1');
      expect(cache.tryTake(connectionString), isNull);
    });

    test('does not reuse SQL Server connections', () async {
      final cache = OdbcStreamingSessionCache();
      const connectionString = 'Driver={ODBC Driver 18 for SQL Server};Server=localhost;';

      expect(
        await cache.offer(connectionString: connectionString, connectionId: 'conn-1'),
        isFalse,
      );
      expect(cache.tryTake(connectionString), isNull);
    });

    test('does not reuse SQL Anywhere connections', () async {
      final cache = OdbcStreamingSessionCache();
      const connectionString = 'Driver={SQL Anywhere 17};dbf=C:/data.db;';

      expect(
        await cache.offer(connectionString: connectionString, connectionId: '42'),
        isFalse,
      );
      expect(cache.tryTake(connectionString), isNull);
    });

    test('expires cached sessions after TTL', () async {
      var now = DateTime.utc(2026, 6, 16, 12);
      final cache = OdbcStreamingSessionCache(
        ttl: const Duration(seconds: 5),
        clock: () => now,
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      await cache.offer(connectionString: connectionString, connectionId: 'pg-1');
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
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      await cache.offer(connectionString: connectionString, connectionId: 'conn-1');
      await cache.offer(
        connectionString: 'Driver={PostgreSQL};Server=other;',
        connectionId: 'conn-2',
      );
      expect(cache.entryCount, 2);

      final drainResult = await cache.drainCachedSessions();

      expect(drainResult.isSuccess(), isTrue);
      expect(cache.entryCount, 0);
      expect(disconnected, containsAll(<String>['conn-1', 'conn-2']));
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
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      expect(
        await cache.offer(connectionString: connectionString, connectionId: 'conn-1'),
        isTrue,
      );

      final drainResult = await cache.drainCachedSessions();

      expect(drainResult.isError(), isTrue);
      expect(drainResult.exceptionOrNull(), isA<domain.ConnectionFailure>());
      expect(cache.entryCount, 0);
    });

    test('tryTake of an expired session calls disconnect', () async {
      var now = DateTime.utc(2026, 6, 16, 12);
      final disconnected = <String>[];
      final cache = OdbcStreamingSessionCache(
        ttl: const Duration(seconds: 5),
        clock: () => now,
        disconnectConnection: (connectionId) async {
          disconnected.add(connectionId);
          return const Success(unit);
        },
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      await cache.offer(connectionString: connectionString, connectionId: 'pg-expired');
      now = now.add(const Duration(seconds: 6));

      expect(cache.tryTake(connectionString), isNull);
      await cache.drainCachedSessions();
      expect(disconnected, ['pg-expired']);
    });

    test('offer awaits disconnect of the replaced session', () async {
      final disconnected = <String>[];
      final cache = OdbcStreamingSessionCache(
        disconnectConnection: (connectionId) async {
          disconnected.add(connectionId);
          return const Success(unit);
        },
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      expect(
        await cache.offer(connectionString: connectionString, connectionId: 'pg-old'),
        isTrue,
      );
      expect(
        await cache.offer(connectionString: connectionString, connectionId: 'pg-new'),
        isTrue,
      );

      expect(disconnected, ['pg-old']);
      expect(cache.tryTake(connectionString), 'pg-new');
    });

    test('offer awaits disconnect of the oldest session when the cache is full', () async {
      final disconnected = <String>[];
      var now = DateTime.utc(2026, 6, 16, 12);
      final cache = OdbcStreamingSessionCache(
        maxEntries: 1,
        clock: () => now,
        disconnectConnection: (connectionId) async {
          disconnected.add(connectionId);
          return const Success(unit);
        },
      );

      expect(
        await cache.offer(
          connectionString: 'Driver={PostgreSQL};Server=one;',
          connectionId: 'pg-1',
        ),
        isTrue,
      );
      now = now.add(const Duration(milliseconds: 1));
      expect(
        await cache.offer(
          connectionString: 'Driver={PostgreSQL};Server=two;',
          connectionId: 'pg-2',
        ),
        isTrue,
      );

      expect(disconnected, ['pg-1']);
      expect(cache.entryCount, 1);
    });

    test('timed-out eviction disconnect is not offered back and drain still completes', () async {
      var now = DateTime.utc(2026, 6, 16, 12);
      final delayed = Completer<Result<void>>();
      final cache = OdbcStreamingSessionCache(
        ttl: const Duration(seconds: 5),
        clock: () => now,
        disconnectTracker: OdbcStreamingDisconnectTracker(
          observedTimeout: const Duration(milliseconds: 20),
        ),
        disconnectConnection: (connectionId) => delayed.future,
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      await cache.offer(connectionString: connectionString, connectionId: 'pg-expired');
      now = now.add(const Duration(seconds: 6));
      expect(cache.tryTake(connectionString), isNull);

      final drainResult = await cache.drainCachedSessions();
      expect(drainResult.isError(), isTrue);
      final failure = drainResult.exceptionOrNull()! as domain.Failure;
      expect(failure.context['reason'], OdbcContextConstants.streamDisconnectStillInFlightReason);
      expect(failure.context['discarded'], isTrue);
      expect(cache.tryTake(connectionString), isNull);
      expect(cache.entryCount, 0);

      delayed.complete(const Success(unit));
      final afterComplete = await cache.drainCachedSessions();
      expect(afterComplete.isSuccess(), isTrue);
      expect(cache.inFlightDisconnectCount, 0);
    });

    test('drain after invalidate disconnects cached sessions', () async {
      final disconnected = <String>[];
      final cache = OdbcStreamingSessionCache(
        disconnectConnection: (connectionId) async {
          disconnected.add(connectionId);
          return const Success(unit);
        },
      );
      const connectionString = 'Driver={PostgreSQL};Server=localhost;';

      await cache.offer(connectionString: connectionString, connectionId: 'pg-1');
      cache.invalidate(connectionString: connectionString);
      expect(cache.entryCount, 0);

      await cache.drainCachedSessions();
      expect(disconnected, ['pg-1']);
    });
  });
}
