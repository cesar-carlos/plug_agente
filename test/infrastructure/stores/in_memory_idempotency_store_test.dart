import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';

void main() {
  group('InMemoryIdempotencyStore', () {
    test('should return null when key not found', () {
      final store = InMemoryIdempotencyStore();

      expect(store.get('missing'), isNull);
    });

    test('should return cached response within TTL', () {
      final now = DateTime.utc(2026, 3, 12, 10);
      final store = InMemoryIdempotencyStore(
        nowProvider: () => now,
      );

      final response = RpcResponse.success(
        id: 'req-1',
        result: <String, dynamic>{'x': 1},
      );
      store.set('key-1', response, const Duration(minutes: 5));

      expect(store.get('key-1'), isNotNull);
      expect(store.get('key-1')!.result, equals(response.result));
    });

    test('should return null after TTL expires', () {
      var now = DateTime.utc(2026, 3, 12, 10);
      final store = InMemoryIdempotencyStore(
        nowProvider: () => now,
      );

      final response = RpcResponse.success(
        id: 'req-1',
        result: <String, dynamic>{},
      );
      store.set('key-1', response, const Duration(minutes: 5));

      now = now.add(const Duration(minutes: 6));

      expect(store.get('key-1'), isNull);
    });

    test(
      'should evict least recently used entry when max entries is reached',
      () {
        final now = DateTime.utc(2026, 3, 12, 10);
        final store = InMemoryIdempotencyStore(
          nowProvider: () => now,
          maxEntries: 2,
        );

        store.set(
          'key-1',
          RpcResponse.success(id: 'req-1', result: const <String, dynamic>{}),
          const Duration(minutes: 5),
        );
        store.set(
          'key-2',
          RpcResponse.success(id: 'req-2', result: const <String, dynamic>{}),
          const Duration(minutes: 5),
        );

        // Mark key-1 as recently used, so key-2 becomes LRU.
        expect(store.get('key-1'), isNotNull);

        store.set(
          'key-3',
          RpcResponse.success(id: 'req-3', result: const <String, dynamic>{}),
          const Duration(minutes: 5),
        );

        expect(store.get('key-1'), isNotNull);
        expect(store.get('key-2'), isNull);
        expect(store.get('key-3'), isNotNull);
      },
    );

    test('should throw when maxEntries is less than 1', () {
      expect(
        () => InMemoryIdempotencyStore(maxEntries: 0),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
