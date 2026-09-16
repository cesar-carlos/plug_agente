import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_disconnect_tracker.dart';
import 'package:result_dart/result_dart.dart';

void main() {
  group('OdbcStreamingDisconnectTracker', () {
    test('keeps a timed-out disconnect in flight and drain completes after it finishes', () async {
      final delayed = Completer<Result<void>>();
      final tracker = OdbcStreamingDisconnectTracker(
        observedTimeout: const Duration(milliseconds: 20),
      );

      final observed = await tracker.run(
        connectionId: 'conn-1',
        disconnect: (_) => delayed.future,
      );

      expect(observed.isError(), isTrue);
      final failure = observed.exceptionOrNull()! as domain.Failure;
      expect(failure.context['reason'], OdbcContextConstants.streamCancelDisconnectTimeoutReason);
      expect(failure.context['discarded'], isTrue);
      expect(tracker.inFlightCount, 1);

      delayed.complete(const Success(unit));
      await tracker.drain();
      expect(tracker.inFlightCount, 0);
    });

    test('drain with timeout completes even if native disconnect never returns', () async {
      final tracker = OdbcStreamingDisconnectTracker(
        observedTimeout: const Duration(milliseconds: 20),
      );
      unawaited(
        tracker.run(
          connectionId: 'conn-stuck',
          disconnect: (_) => Completer<Result<void>>().future,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await tracker.drain(timeout: const Duration(milliseconds: 20));
      expect(tracker.inFlightCount, 1);
    });

    test('does not treat the connection as reusable after disconnect failure', () async {
      final tracker = OdbcStreamingDisconnectTracker();
      final result = await tracker.run(
        connectionId: 'conn-fail',
        disconnect: (_) async => Failure(Exception('disconnect failed')),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.Failure;
      expect(failure.context['discarded'], isTrue);
      expect(tracker.inFlightCount, 0);
    });

    test('deduplicates work and rejects new cleanup when the bounded queue is full', () async {
      final first = Completer<Result<void>>();
      final second = Completer<Result<void>>();
      var firstStarts = 0;
      var secondStarts = 0;
      final tracker = OdbcStreamingDisconnectTracker(
        maxInFlight: 1,
        maxPending: 1,
        observedTimeout: const Duration(seconds: 1),
      );

      unawaited(
        tracker.run(
          connectionId: 'conn-1',
          disconnect: (_) {
            firstStarts++;
            return first.future;
          },
        ),
      );
      unawaited(
        tracker.run(
          connectionId: 'conn-2',
          disconnect: (_) {
            secondStarts++;
            return second.future;
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final duplicate = tracker.run(
        connectionId: 'conn-1',
        disconnect: (_) => Future<Result<void>>.error(StateError('must not start twice')),
      );
      final saturated = await tracker.run(
        connectionId: 'conn-3',
        disconnect: (_) async => const Success(unit),
      );
      expect(firstStarts, 1);
      expect(secondStarts, 0);
      expect(tracker.runningCount, 1);
      expect(tracker.pendingCount, 1);
      expect(saturated.isError(), isTrue);

      first.complete(const Success(unit));
      await duplicate;
      await Future<void>.delayed(Duration.zero);
      expect(secondStarts, 1);
      second.complete(const Success(unit));
      await tracker.drain();
    });
  });
}
