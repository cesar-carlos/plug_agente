import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/agent_action_captured_output_periodic_purge.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:result_dart/result_dart.dart';

void main() {
  group('AgentActionCapturedOutputPeriodicPurge', () {
    test('should invoke purge when purgeNow completes', () async {
      var calls = 0;
      final sut = AgentActionCapturedOutputPeriodicPurge(({DateTime? now}) async {
        expect(now, isNull);
        calls++;
        return const Success(2);
      });

      await sut.purgeNow();

      expect(calls, 1);
    });

    test('should complete when purge returns Failure', () async {
      final sut = AgentActionCapturedOutputPeriodicPurge(
        ({DateTime? now}) async => Failure(ServerFailure('db down')),
      );

      await expectLater(sut.purgeNow(), completes);
    });

    test('should keep a single periodic timer when start is called twice', () {
      final sut = AgentActionCapturedOutputPeriodicPurge(
        ({DateTime? now}) async => const Success(0),
        interval: const Duration(days: 365),
      );

      sut.start();
      sut.start();
      expect(sut.isRunning, isTrue);

      sut.stop();
      expect(sut.isRunning, isFalse);
    });
  });
}
