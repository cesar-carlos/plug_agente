import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/drift_idempotency_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DriftIdempotencyStore', () {
    test('should return null when key not found', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftIdempotencyStore(db);

      expect(await store.getRecord('missing'), isNull);
    });

    test('should persist response and fingerprint with TTL', () async {
      var now = DateTime.utc(2026, 5, 16, 12);
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftIdempotencyStore(
        db,
        nowProvider: () => now,
      );

      final response = RpcResponse.success(
        id: 'req-1',
        result: const <String, dynamic>{'x': 1},
      );
      await store.set('key-a', response, const Duration(minutes: 10), requestFingerprint: 'fp-1');

      final record = await store.getRecord('key-a');
      expect(record, isNotNull);
      expect(record!.requestFingerprint, 'fp-1');
      expect(record.response.error, isNull);
      expect((record.response.result as Map<String, dynamic>)['x'], 1);

      now = now.add(const Duration(minutes: 11));
      expect(await store.getRecord('key-a'), isNull);
    });

    test('purgeExpiredEntries removes expired rows', () async {
      var now = DateTime.utc(2026, 5, 16, 12);
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftIdempotencyStore(
        db,
        nowProvider: () => now,
      );
      await store.set(
        'exp-key',
        RpcResponse.success(id: 'r1', result: const <String, dynamic>{}),
        const Duration(minutes: 5),
      );
      expect(await store.getRecord('exp-key'), isNotNull);
      now = now.add(const Duration(minutes: 6));
      expect(await store.purgeExpiredEntries(referenceTime: now), 1);
      expect(await store.getRecord('exp-key'), isNull);
    });

    test('should evict oldest entries when maxEntries is exceeded', () async {
      var tick = 0;
      DateTime now() => DateTime.utc(2026, 5, 16, 12).add(Duration(seconds: tick++));
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftIdempotencyStore(
        db,
        maxEntries: 2,
        nowProvider: now,
      );

      await store.set(
        'key-1',
        RpcResponse.success(id: 'r1', result: const <String, dynamic>{}),
        const Duration(hours: 1),
      );
      await store.set(
        'key-2',
        RpcResponse.success(id: 'r2', result: const <String, dynamic>{}),
        const Duration(hours: 1),
      );

      expect(await store.getRecord('key-1'), isNotNull);

      await store.set(
        'key-3',
        RpcResponse.success(id: 'r3', result: const <String, dynamic>{}),
        const Duration(hours: 1),
      );

      expect(await store.getRecord('key-1'), isNotNull);
      expect(await store.getRecord('key-2'), isNull);
      expect(await store.getRecord('key-3'), isNotNull);
    });
  });
}
