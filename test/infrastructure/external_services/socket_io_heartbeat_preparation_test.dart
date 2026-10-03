import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';

void main() {
  test('pending preparation prevents overlap and reset cannot clear a new preparation', () {
    fakeAsync((clock) {
      final gates = <Completer<bool>>[];
      final controller = SocketIoHeartbeatController(
        isConnected: () => true,
        emitHeartbeat: () {
          final gate = Completer<bool>();
          gates.add(gate);
          return gate.future;
        },
        logMessage: (_, _, _) {},
        onConnectionStale: () {},
        interval: const Duration(seconds: 2),
        ackTimeout: const Duration(seconds: 1),
      );
      controller.start();
      clock.elapse(const Duration(seconds: 8));
      expect(gates, hasLength(1));
      expect(controller.skippedPreparationTicks, 4);
      controller.start();
      expect(gates, hasLength(2));
      gates[0].complete(true);
      clock.flushMicrotasks();
      expect(controller.isPreparing, isTrue);
      controller.stop();
      gates[1].complete(true);
      clock.flushMicrotasks();
      expect(controller.isPreparing, isFalse);
    });
  });

  test('a thrown preparation is handled without counting a missed ACK', () {
    fakeAsync((clock) {
      final events = <String>[];
      final controller = SocketIoHeartbeatController(
        isConnected: () => true,
        emitHeartbeat: () async => throw StateError('encode'),
        logMessage: (_, event, _) => events.add(event),
        onConnectionStale: () {},
        interval: const Duration(seconds: 2),
        ackTimeout: const Duration(seconds: 1),
      );
      controller.start();
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      expect(events, ['heartbeat_emit_failed']);
      expect(controller.preparationFailures, 1);
      expect(controller.isPreparing, isFalse);
      controller.stop();
    });
  });
}
