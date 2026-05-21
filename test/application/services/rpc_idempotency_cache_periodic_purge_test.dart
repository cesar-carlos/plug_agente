import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/rpc_idempotency_cache_periodic_purge.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:result_dart/result_dart.dart';

void main() {
  group('RpcIdempotencyCachePeriodicPurge', () {
    test('should invoke purge when purgeNow completes', () async {
      var calls = 0;
      final sut = RpcIdempotencyCachePeriodicPurge(({DateTime? referenceTime}) async {
        expect(referenceTime, isNull);
        calls++;
        return const Success(3);
      });

      await sut.purgeNow();

      expect(calls, 1);
    });

    test('should complete when purge returns Failure', () async {
      final sut = RpcIdempotencyCachePeriodicPurge(
        ({DateTime? referenceTime}) async => Failure(ServerFailure('db down')),
      );

      await expectLater(sut.purgeNow(), completes);
    });

    test('should keep a single periodic timer when start is called twice', () {
      final sut = RpcIdempotencyCachePeriodicPurge(
        ({DateTime? referenceTime}) async => const Success(0),
        interval: const Duration(days: 365),
      );

      sut.start();
      sut.start();
      expect(sut.isRunning, isTrue);

      sut.stop();
      expect(sut.isRunning, isFalse);
    });

    test('should allow stop before start', () {
      final sut = RpcIdempotencyCachePeriodicPurge(
        ({DateTime? referenceTime}) async => const Success(0),
      );

      sut.stop();

      expect(sut.isRunning, isFalse);
    });
  });
}
