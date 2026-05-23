import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/async_operation_gate.dart';

void main() {
  group('AsyncOperationGate', () {
    test('should serialize concurrent operations', () async {
      final gate = AsyncOperationGate();
      var inFlight = 0;
      var maxConcurrent = 0;
      var actionCalls = 0;
      Completer<void>? firstGate;

      Future<int> runOp() {
        return gate.runSerialized(() async {
          actionCalls++;
          inFlight++;
          if (inFlight > maxConcurrent) {
            maxConcurrent = inFlight;
          }
          try {
            if (actionCalls == 1) {
              firstGate ??= Completer<void>();
              await firstGate!.future;
            }
            return actionCalls;
          } finally {
            inFlight--;
          }
        });
      }

      final first = runOp();
      while (actionCalls < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      final second = runOp();

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(actionCalls, 1);
      expect(maxConcurrent, 1);

      firstGate?.complete();
      await Future.wait([first, second]);

      expect(actionCalls, 2);
      expect(maxConcurrent, 1);
    });

    test('should return staleResult when epoch is invalidated before action runs', () async {
      final gate = AsyncOperationGate();
      Completer<void>? blockMutex;

      final blocked = gate.runSerialized(() async {
        blockMutex ??= Completer<void>();
        await blockMutex!.future;
        return 'ran';
      });

      while (blockMutex == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final stale = gate.runSerialized(
        () async => 'should-not-run',
        staleResult: 'stale',
      );

      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.invalidateEpoch();

      blockMutex?.complete();
      await blocked;

      expect(await stale, 'stale');
    });

    test('should throw when epoch is stale and staleResult is not provided', () async {
      final gate = AsyncOperationGate();
      Completer<void>? blockMutex;

      final blocked = gate.runSerialized(() async {
        blockMutex ??= Completer<void>();
        await blockMutex!.future;
        return 'ran';
      });

      while (blockMutex == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final staleFuture = gate.runSerialized(() async => 'should-not-run');

      await Future<void>.delayed(const Duration(milliseconds: 5));
      gate.invalidateEpoch();

      blockMutex?.complete();
      await blocked;

      await expectLater(
        staleFuture,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('is stale'),
          ),
        ),
      );
    });

    test('should abort when shouldAbort returns true before action runs', () async {
      final gate = AsyncOperationGate();
      var aborted = false;

      final result = await gate.runSerialized(
        () async {
          aborted = true;
          return 'ran';
        },
        staleResult: 'aborted',
        shouldAbort: () => true,
      );

      expect(result, 'aborted');
      expect(aborted, isFalse);
    });
  });

  group('ExclusiveRecoveryGate', () {
    test('should coalesce concurrent schedules into one handler run', () async {
      final recoveryGate = ExclusiveRecoveryGate();
      var handlerRuns = 0;
      var maxConcurrentHandlers = 0;
      var inFlightHandlers = 0;
      Completer<void>? handlerGate;

      Future<void> handler() async {
        handlerRuns++;
        inFlightHandlers++;
        if (inFlightHandlers > maxConcurrentHandlers) {
          maxConcurrentHandlers = inFlightHandlers;
        }
        handlerGate ??= Completer<void>();
        await handlerGate!.future;
        inFlightHandlers--;
      }

      unawaited(recoveryGate.schedule(
        handler: handler,
        shouldAbort: () => false,
        shouldSkipAfterLock: () => false,
      ));
      unawaited(recoveryGate.schedule(
        handler: handler,
        shouldAbort: () => false,
        shouldSkipAfterLock: () => false,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handlerRuns, 1);
      expect(maxConcurrentHandlers, 1);

      handlerGate?.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(handlerRuns, 1);
    });

    test('should skip handler when shouldSkipAfterLock returns true', () async {
      final recoveryGate = ExclusiveRecoveryGate();
      var handlerRuns = 0;
      var skipped = false;

      await recoveryGate.schedule(
        handler: () async {
          handlerRuns++;
        },
        shouldAbort: () => false,
        shouldSkipAfterLock: () => true,
        onSkippedAfterLock: () {
          skipped = true;
        },
      );

      expect(handlerRuns, 0);
      expect(skipped, isTrue);
    });

    test('should invoke onCoalesced when a schedule is already pending', () async {
      final recoveryGate = ExclusiveRecoveryGate();
      var coalesced = false;
      Completer<void>? handlerGate;

      unawaited(recoveryGate.schedule(
        handler: () async {
          handlerGate ??= Completer<void>();
          await handlerGate!.future;
        },
        shouldAbort: () => false,
        shouldSkipAfterLock: () => false,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 5));

      await recoveryGate.schedule(
        handler: () async {},
        shouldAbort: () => false,
        shouldSkipAfterLock: () => false,
        onCoalesced: () {
          coalesced = true;
        },
      );

      expect(coalesced, isTrue);
      handlerGate?.complete();
    });
  });
}
