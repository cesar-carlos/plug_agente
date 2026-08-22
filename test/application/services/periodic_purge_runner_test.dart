import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/periodic_purge_runner.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ServerFailure;
import 'package:result_dart/result_dart.dart';

void main() {
  group('PeriodicPurgeRunner', () {
    test('should skip overlapping purgeNow while a previous purge is in flight', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;
      final runner = PeriodicPurgeRunner(
        purge: () async {
          calls += 1;
          started.complete();
          await release.future;
          return const Success(1);
        },
        interval: const Duration(days: 365),
        logName: 'periodic_purge_runner_test',
        successLogMessage: (count) => 'purged $count',
        failureLogMessage: 'purge failed',
      );

      final first = runner.purgeNow();
      await started.future;
      final second = runner.purgeNow();
      await second;
      expect(calls, 1);

      release.complete();
      await first;
      expect(calls, 1);
    });

    test('should complete when purge returns Failure', () async {
      final runner = PeriodicPurgeRunner(
        purge: () async => Failure(ServerFailure('db down')),
        interval: const Duration(days: 365),
        logName: 'periodic_purge_runner_test',
        successLogMessage: (count) => 'purged $count',
        failureLogMessage: 'purge failed',
      );

      await expectLater(runner.purgeNow(), completes);
    });
  });
}
