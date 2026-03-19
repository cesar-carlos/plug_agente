import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';

void main() {
  group('SocketIoHeartbeatController', () {
    test('should call onConnectionStale after max missed acks', () async {
      final connected = true;
      final staleCalls = <int>[];

      final controller = SocketIoHeartbeatController(
        isConnected: () => connected,
        emitHeartbeat: () {},
        logMessage: (String direction, String event, dynamic data) {},
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
      final connected = true;
      final staleCalls = <int>[];

      final controller = SocketIoHeartbeatController(
        isConnected: () => connected,
        emitHeartbeat: () {},
        logMessage: (String direction, String event, dynamic data) {},
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
  });
}
