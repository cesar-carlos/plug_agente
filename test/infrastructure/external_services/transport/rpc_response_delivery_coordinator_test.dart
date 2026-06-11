import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_delivery_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class _MockRpcResponsePreparer extends Mock implements RpcResponsePreparer {}

class _MockSocket extends Mock implements io.Socket {}

void main() {
  group('RpcResponseDeliveryCoordinator', () {
    late _MockRpcResponsePreparer responsePreparer;
    late _MockSocket socket;
    late List<({String direction, String event, dynamic data})> logs;
    late List<dynamic> internalErrorRequestIds;
    late bool deliveryGuaranteesEnabled;

    setUp(() {
      responsePreparer = _MockRpcResponsePreparer();
      socket = _MockSocket();
      logs = <({String direction, String event, dynamic data})>[];
      internalErrorRequestIds = <dynamic>[];
      deliveryGuaranteesEnabled = false;

      when(() => socket.connected).thenReturn(true);
      when(() => socket.emit(any<String>(), any<dynamic>())).thenReturn(null);
    });

    RpcResponseDeliveryCoordinator createCoordinator({
      int connectGeneration = 1,
      io.Socket? Function()? activeSocket,
    }) {
      return RpcResponseDeliveryCoordinator(
        responsePreparer: responsePreparer,
        prepareOutgoingPayload: (_, payload) async => Success(payload as Map<String, dynamic>),
        logMessage: (direction, event, data) => logs.add((direction: direction, event: event, data: data)),
        deliveryGuaranteesEnabled: () => deliveryGuaranteesEnabled,
        activeSocket: activeSocket ?? () => socket,
        connectGeneration: () => connectGeneration,
        metricsCollector: null,
        emitInternalErrorResponse: (requestId) async => internalErrorRequestIds.add(requestId),
      );
    }

    test('extractResponseId returns rpc id for single and batch responses', () {
      expect(
        RpcResponseDeliveryCoordinator.extractResponseId(
          RpcResponse.success(id: 'req-1', result: const {'ok': true}),
        ),
        'req-1',
      );
      expect(
        RpcResponseDeliveryCoordinator.extractResponseId(
          <RpcResponse>[
            RpcResponse.success(id: 'req-1', result: const {'ok': true}),
            RpcResponse.success(id: 'req-2', result: const {'ok': true}),
          ],
        ),
        'req-1',
      );
    });

    test('emits rpc:response without ack when delivery guarantees are disabled', () async {
      final response = RpcResponse.success(id: 'req-1', result: const {'rows': <Object?>[]});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-1',
        'result': const {'rows': <Object?>[]},
      };
      when(() => responsePreparer.prepareForSend(response)).thenReturn(prepared);
      when(
        () => responsePreparer.validateOutgoing(prepared, methodsById: any(named: 'methodsById')),
      ).thenReturn(Success(prepared));

      final coordinator = createCoordinator();
      await coordinator.emit(response);

      verify(() => socket.emit('rpc:response', prepared)).called(1);
      expect(logs, hasLength(1));
      expect(logs.single.event, 'rpc:response');
    });

    test('emits internal error when outgoing validation fails', () async {
      final response = RpcResponse.success(id: 'req-9', result: const {'rows': <Object?>[]});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-9',
        'result': const {'rows': <Object?>[]},
      };
      when(() => responsePreparer.prepareForSend(response)).thenReturn(prepared);
      when(
        () => responsePreparer.validateOutgoing(prepared, methodsById: any(named: 'methodsById')),
      ).thenReturn(Failure(Exception('invalid')));

      final coordinator = createCoordinator();
      await coordinator.emit(response);

      expect(internalErrorRequestIds, ['req-9']);
      verifyNever(() => socket.emit(any<String>(), any<dynamic>()));
    });

    test('skips emit when socket is disconnected', () async {
      final response = RpcResponse.success(id: 'req-3', result: const {'ok': true});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-3',
        'result': const {'ok': true},
      };
      when(() => responsePreparer.prepareForSend(response)).thenReturn(prepared);
      when(
        () => responsePreparer.validateOutgoing(prepared, methodsById: any(named: 'methodsById')),
      ).thenReturn(Success(prepared));

      final coordinator = createCoordinator(activeSocket: () => null);
      await coordinator.emit(response);

      verifyNever(() => socket.emit(any<String>(), any<dynamic>()));
    });
  });
}
