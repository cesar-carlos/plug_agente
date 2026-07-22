import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';

void main() {
  group('SocketIoHeartbeatController', () {
    test('should assert when ackTimeout >= interval', () {
      expect(
        () => SocketIoHeartbeatController(
          isConnected: () => true,
          emitHeartbeat: () async => true,
          logMessage: (_, _, _) {},
          onConnectionStale: () {},
          interval: const Duration(milliseconds: 10),
          ackTimeout: const Duration(milliseconds: 10), // equal — should fail assert
          maxMissed: 2,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('should call onConnectionStale after max missed acks', () async {
      const connected = true;
      final staleCalls = <int>[];

      final controller = SocketIoHeartbeatController(
        isConnected: () => connected,
        emitHeartbeat: () async => true,
        logMessage: (_, _, _) {},
        onConnectionStale: () => staleCalls.add(1),
        interval: const Duration(milliseconds: 10),
        ackTimeout: const Duration(milliseconds: 5),
        maxMissed: 2,
      );

      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      controller.stop();

      expect(staleCalls, [1]);
    });

    test('onAckReceived resets missed count', () async {
      const connected = true;
      final staleCalls = <int>[];

      final controller = SocketIoHeartbeatController(
        isConnected: () => connected,
        emitHeartbeat: () async => true,
        logMessage: (_, _, _) {},
        onConnectionStale: () => staleCalls.add(1),
        interval: const Duration(milliseconds: 20),
        ackTimeout: const Duration(milliseconds: 8),
        maxMissed: 5,
      );

      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 12));
      controller.onAckReceived();
      await Future<void>.delayed(const Duration(milliseconds: 12));
      controller.onAckReceived();
      controller.stop();

      expect(staleCalls, isEmpty);
    });

    test('failed emit does not arm ack wait or count as miss', () async {
      final staleCalls = <int>[];
      final logs = <String>[];
      var emitCalls = 0;

      final controller = SocketIoHeartbeatController(
        isConnected: () => true,
        emitHeartbeat: () async {
          emitCalls++;
          return false;
        },
        logMessage: (direction, event, _) {
          logs.add('$direction:$event');
        },
        onConnectionStale: () => staleCalls.add(1),
        interval: const Duration(milliseconds: 20),
        ackTimeout: const Duration(milliseconds: 8),
        maxMissed: 2,
      );

      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 55));
      controller.stop();

      expect(emitCalls, greaterThanOrEqualTo(2));
      expect(logs, everyElement(contains('heartbeat_emit_failed')));
      expect(staleCalls, isEmpty);
    });
  });
}
