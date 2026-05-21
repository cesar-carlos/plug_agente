import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/cleanup_expired_rpc_idempotency_cache.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/stores/drift_idempotency_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CleanupExpiredRpcIdempotencyCache', () {
    test('should return zero when cache is empty', () async {
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftIdempotencyStore(db);
      final useCase = CleanupExpiredRpcIdempotencyCache(store);

      final result = await useCase();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 0);
    });

    test('should purge expired rows using explicit clock', () async {
      var now = DateTime.utc(2026, 5, 16, 14);
      final db = AppDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final store = DriftIdempotencyStore(
        db,
        nowProvider: () => now,
      );
      await store.set(
        'k-exp',
        RpcResponse.success(id: 'r1', result: const <String, dynamic>{}),
        const Duration(minutes: 5),
      );
      now = now.add(const Duration(minutes: 10));
      final useCase = CleanupExpiredRpcIdempotencyCache(store);

      final result = await useCase(referenceTime: now);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 1);
      expect(await store.getRecord('k-exp'), isNull);
    });
  });
}
