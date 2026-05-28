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
      // Disable the LRU update throttle so the second-by-second tick fixture
      // exercises the eviction order contract directly; the dedicated throttle
      // group below covers the throttled hot-key behaviour.
      final store = DriftIdempotencyStore(
        db,
        maxEntries: 2,
        lruUpdateMinInterval: Duration.zero,
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

    group('LRU update throttle', () {
      test(
        'should skip updated_at refresh while interval is not elapsed',
        () async {
          var now = DateTime.utc(2026, 5, 16, 12);
          final db = AppDatabase(executor: NativeDatabase.memory());
          addTearDown(db.close);
          // Default throttle interval (1 min) applies; reads at +30s should
          // not refresh updated_at.
          final store = DriftIdempotencyStore(
            db,
            nowProvider: () => now,
          );

          await store.set(
            'hot-key',
            RpcResponse.success(id: 'r1', result: const <String, dynamic>{}),
            const Duration(hours: 1),
          );

          // First read at +30s: within throttle window, should not refresh
          // updated_at. We observe the throttled behaviour by then forcing an
          // eviction and checking the entry is still treated as oldest.
          now = now.add(const Duration(seconds: 30));
          expect(await store.getRecord('hot-key'), isNotNull);

          // Insert a newer entry, then a third entry that triggers eviction
          // with maxEntries=2. The hot-key's updated_at was never refreshed
          // beyond the initial set, so it is the oldest and gets evicted.
          final tightStore = DriftIdempotencyStore(
            db,
            maxEntries: 2,
            nowProvider: () => now,
          );
          now = now.add(const Duration(seconds: 5));
          await tightStore.set(
            'newer-key',
            RpcResponse.success(id: 'r2', result: const <String, dynamic>{}),
            const Duration(hours: 1),
          );
          now = now.add(const Duration(seconds: 5));
          await tightStore.set(
            'newest-key',
            RpcResponse.success(id: 'r3', result: const <String, dynamic>{}),
            const Duration(hours: 1),
          );

          expect(await tightStore.getRecord('hot-key'), isNull);
          expect(await tightStore.getRecord('newer-key'), isNotNull);
          expect(await tightStore.getRecord('newest-key'), isNotNull);
        },
      );

      test('should refresh updated_at once the throttle interval elapses', () async {
        var now = DateTime.utc(2026, 5, 16, 12);
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final store = DriftIdempotencyStore(
          db,
          maxEntries: 2,
          nowProvider: () => now,
        );

        await store.set(
          'key-a',
          RpcResponse.success(id: 'r1', result: const <String, dynamic>{}),
          const Duration(hours: 1),
        );
        now = now.add(const Duration(seconds: 10));
        await store.set(
          'key-b',
          RpcResponse.success(id: 'r2', result: const <String, dynamic>{}),
          const Duration(hours: 1),
        );

        // Advance past the throttle window then read key-a: this MUST refresh
        // its updated_at so the eviction below picks key-b instead.
        now = now.add(const Duration(minutes: 2));
        expect(await store.getRecord('key-a'), isNotNull);

        now = now.add(const Duration(seconds: 5));
        await store.set(
          'key-c',
          RpcResponse.success(id: 'r3', result: const <String, dynamic>{}),
          const Duration(hours: 1),
        );

        expect(await store.getRecord('key-a'), isNotNull);
        expect(await store.getRecord('key-b'), isNull);
        expect(await store.getRecord('key-c'), isNotNull);
      });

      test('should reject negative throttle interval', () {
        final db = AppDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        expect(
          () => DriftIdempotencyStore(
            db,
            lruUpdateMinInterval: const Duration(microseconds: -1),
          ),
          throwsArgumentError,
        );
      });
    });
  });
}
