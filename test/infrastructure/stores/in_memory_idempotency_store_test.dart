import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';

void main() {
  group('InMemoryIdempotencyStore', () {
    test('should return null when key not found', () async {
      final store = InMemoryIdempotencyStore();

      expect(await store.get('missing'), isNull);
    });

    test('should strip null optional fields from cached result on read', () async {
      final store = InMemoryIdempotencyStore();
      await store.set(
        'key-null-field',
        RpcResponse.success(
          id: 'req-1',
          result: <String, dynamic>{
            'row_count': 0,
            'affected_rows': null,
          },
        ),
        const Duration(minutes: 5),
      );

      final cached = await store.get('key-null-field');
      final result = cached!.result as Map<String, dynamic>;

      expect(result.containsKey('affected_rows'), isFalse);
      expect(result['row_count'], 0);
    });

    test('should return cached response within TTL', () async {
      final now = DateTime.utc(2026, 3, 12, 10);
      final store = InMemoryIdempotencyStore(
        nowProvider: () => now,
      );

      final response = RpcResponse.success(
        id: 'req-1',
        result: <String, dynamic>{'x': 1},
      );
      await store.set('key-1', response, const Duration(minutes: 5));

      expect(await store.get('key-1'), isNotNull);
      expect((await store.get('key-1'))!.result, equals(response.result));
    });

    test('should return null after TTL expires', () async {
      var now = DateTime.utc(2026, 3, 12, 10);
      final store = InMemoryIdempotencyStore(
        nowProvider: () => now,
      );

      final response = RpcResponse.success(
        id: 'req-1',
        result: <String, dynamic>{},
      );
      await store.set('key-1', response, const Duration(minutes: 5));

      now = now.add(const Duration(minutes: 6));

      expect(await store.get('key-1'), isNull);
    });

    test(
      'should evict least recently used entry when max entries is reached',
      () async {
        final now = DateTime.utc(2026, 3, 12, 10);
        final store = InMemoryIdempotencyStore(
          nowProvider: () => now,
          maxEntries: 2,
        );

        await store.set(
          'key-1',
          RpcResponse.success(id: 'req-1', result: const <String, dynamic>{}),
          const Duration(minutes: 5),
        );
        await store.set(
          'key-2',
          RpcResponse.success(id: 'req-2', result: const <String, dynamic>{}),
          const Duration(minutes: 5),
        );

        // Mark key-1 as recently used, so key-2 becomes LRU.
        expect(await store.get('key-1'), isNotNull);

        await store.set(
          'key-3',
          RpcResponse.success(id: 'req-3', result: const <String, dynamic>{}),
          const Duration(minutes: 5),
        );

        expect(await store.get('key-1'), isNotNull);
        expect(await store.get('key-2'), isNull);
        expect(await store.get('key-3'), isNotNull);
      },
    );

    test('purgeExpiredEntries removes expired keys', () async {
      var now = DateTime.utc(2026, 3, 12, 10);
      final store = InMemoryIdempotencyStore(
        nowProvider: () => now,
      );
      await store.set(
        'a',
        RpcResponse.success(id: 'req-1', result: const <String, dynamic>{}),
        const Duration(minutes: 1),
      );
      now = now.add(const Duration(minutes: 2));
      expect(await store.purgeExpiredEntries(referenceTime: now), 1);
      expect(await store.get('a'), isNull);
    });

    test('should throw when maxEntries is less than 1', () {
      expect(
        () => InMemoryIdempotencyStore(maxEntries: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
