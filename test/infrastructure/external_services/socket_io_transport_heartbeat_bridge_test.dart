import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_heartbeat_controller.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_heartbeat_bridge.dart';

void main() {
  test('mixed ACK decodes keep arrival order and retain trace correlation', () {
    fakeAsync((clock) {
      final decode = Completer<dynamic>();
      final logged = <bool>[];
      late final SocketIoHeartbeatController heartbeat;
      heartbeat = SocketIoHeartbeatController(
        isConnected: () => true,
        emitHeartbeat: () async => true,
        emitHeartbeatWithEpoch: (epoch) async {
          heartbeat.registerExpectedTraceId('expected', epoch);
          return true;
        },
        logMessage: (_, _, _) {},
        onConnectionStale: () => fail('unexpected timeout'),
      );
      final bridge = SocketIoTransportHeartbeatBridge(
        heartbeat: heartbeat,
        agentIdProvider: () => 'agent',
        protocolNameProvider: () => 'jsonrpc-v2',
        emitEventAsync: (_, _) async => true,
        logMessage: (_, _, data) => logged.add((data as Map)['accepted'] as bool),
        decodeIncomingPayload: (data, {required sourceEvent}) => data,
        decodeIncomingPayloadAsync: (data, {required sourceEvent}) => decode.future,
        shouldDecodeAsync: (data) => data == 'gzip',
      );
      heartbeat.start();
      clock.flushMicrotasks();
      bridge.handleHeartbeatAck('gzip');
      bridge.handleHeartbeatAck({'trace_id': 'expected'});
      expect(logged, isEmpty);
      expect(bridge.diagnostics['pending_ack_decodes'], 1);
      decode.complete({'trace_id': 'wrong'});
      clock.flushMicrotasks();
      expect(logged, [false, true]);
      expect(bridge.diagnostics['pending_ack_decodes'], 0);
      heartbeat.stop();
    });
  });

  test('a decode from a replaced session cannot acknowledge the current beat', () {
    fakeAsync((clock) {
      var session = 0;
      final decode = Completer<dynamic>();
      final logged = <bool>[];
      late final SocketIoHeartbeatController heartbeat;
      heartbeat = SocketIoHeartbeatController(
        isConnected: () => true,
        emitHeartbeat: () async => true,
        emitHeartbeatWithEpoch: (epoch) async {
          heartbeat.registerExpectedTraceId('trace-$session', epoch);
          return true;
        },
        logMessage: (_, _, _) {},
        onConnectionStale: () => fail('unexpected timeout'),
      );
      final bridge = SocketIoTransportHeartbeatBridge(
        heartbeat: heartbeat,
        agentIdProvider: () => 'agent',
        protocolNameProvider: () => 'jsonrpc-v2',
        emitEventAsync: (_, _) async => true,
        logMessage: (_, _, data) => logged.add((data as Map)['accepted'] as bool),
        decodeIncomingPayload: (data, {required sourceEvent}) => data,
        decodeIncomingPayloadAsync: (data, {required sourceEvent}) => decode.future,
        shouldDecodeAsync: (data) => data == 'gzip',
        sessionGeneration: () => session,
      );
      heartbeat.start();
      clock.flushMicrotasks();
      bridge.handleHeartbeatAck('gzip');
      bridge.handleHeartbeatAck({'trace_id': 'trace-0'});
      session++;
      bridge.reset();
      heartbeat.start();
      clock.flushMicrotasks();
      decode.complete({'trace_id': 'trace-1'});
      clock.flushMicrotasks();
      expect(logged, isEmpty);
      expect(heartbeat.ackRejectionReason('trace-1'), isNull);
      bridge.handleHeartbeatAck({'trace_id': 'trace-1'});
      expect(logged, [true]);
      heartbeat.stop();
    });
  });
}
