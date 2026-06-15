import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/idempotency_l1_cache.dart';

void main() {
  group('IdempotencyL1Cache', () {
    test('returns cached record before expiry', () {
      final now = DateTime.utc(2026, 6, 15, 12);
      final cache = IdempotencyL1Cache(nowProvider: () => now);
      final record = IdempotencyRecord(
        response: RpcResponse.success(id: '1', result: const {'ok': true}),
        requestFingerprint: 'fp-1',
      );

      cache.put('key-a', record, now.add(const Duration(minutes: 5)));

      expect(cache.get('key-a'), same(record));
      expect(cache.get('key-a'), same(record));
    });

    test('expires entries after ttl', () {
      final start = DateTime.utc(2026, 6, 15, 12);
      var now = start;
      final cache = IdempotencyL1Cache(nowProvider: () => now);
      final record = IdempotencyRecord(
        response: RpcResponse.success(id: '1', result: const <String, dynamic>{}),
        requestFingerprint: 'fp-2',
      );

      cache.put('key-a', record, now.add(const Duration(minutes: 1)));
      now = now.add(const Duration(minutes: 2));

      expect(cache.get('key-a'), isNull);
    });
  });
}
