import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/agent_action_execution_periodic_purge.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:result_dart/result_dart.dart';

void main() {
  group('AgentActionExecutionPeriodicPurge', () {
    test('should invoke purge when purgeNow completes', () async {
      var calls = 0;
      final sut = AgentActionExecutionPeriodicPurge(({DateTime? referenceTime}) async {
        expect(referenceTime, isNull);
        calls++;
        return const Success(2);
      });

      await sut.purgeNow();

      expect(calls, 1);
    });

    test('should complete when purge returns Failure', () async {
      final sut = AgentActionExecutionPeriodicPurge(
        ({DateTime? referenceTime}) async => Failure(ServerFailure('db down')),
      );

      await expectLater(sut.purgeNow(), completes);
    });

    test('should keep a single periodic timer when start is called twice', () {
      final sut = AgentActionExecutionPeriodicPurge(
        ({DateTime? referenceTime}) async => const Success(0),
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
