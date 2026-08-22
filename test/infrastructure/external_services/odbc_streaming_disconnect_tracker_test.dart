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
  });
}
