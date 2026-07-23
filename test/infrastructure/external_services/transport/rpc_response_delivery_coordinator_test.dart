import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_delivery_coordinator.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
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
    late MetricsCollector metrics;

    setUp(() {
      responsePreparer = _MockRpcResponsePreparer();
      socket = _MockSocket();
      logs = <({String direction, String event, dynamic data})>[];
      internalErrorRequestIds = <dynamic>[];
      deliveryGuaranteesEnabled = false;
      metrics = MetricsCollector();

      when(() => socket.connected).thenReturn(true);
      when(() => socket.emit(any<String>(), any<dynamic>())).thenReturn(null);
    });

    RpcResponseDeliveryCoordinator createCoordinator({
      int connectGeneration = 1,
      io.Socket? Function()? activeSocket,
      int Function()? connectGenerationProvider,
      Duration? responseAckTimeout,
    }) {
      return RpcResponseDeliveryCoordinator(
        responsePreparer: responsePreparer,
        prepareOutgoingPayload: (_, payload) async => Success(payload as Map<String, dynamic>),
        logMessage: (direction, event, data) => logs.add((direction: direction, event: event, data: data)),
        deliveryGuaranteesEnabled: () => deliveryGuaranteesEnabled,
        activeSocket: activeSocket ?? () => socket,
        connectGeneration: connectGenerationProvider ?? () => connectGeneration,
        metricsCollector: metrics,
        emitInternalErrorResponse: (requestId) async => internalErrorRequestIds.add(requestId),
        responseAckTimeout: responseAckTimeout,
      );
    }

    Future<void> prepareValidResponse(RpcResponse response, Map<String, dynamic> prepared) async {
      when(() => responsePreparer.prepareForSend(response)).thenReturn(prepared);
      when(
        () => responsePreparer.validateOutgoing(prepared, methodsById: any(named: 'methodsById')),
      ).thenReturn(Success(prepared));
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
      await prepareValidResponse(response, prepared);

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
      await prepareValidResponse(response, prepared);

      final coordinator = createCoordinator(activeSocket: () => null);
      await coordinator.emit(response);

      verifyNever(() => socket.emit(any<String>(), any<dynamic>()));
    });

    test('completes ACK delivery when hub returns empty ACK (0 args)', () async {
      deliveryGuaranteesEnabled = true;
      final response = RpcResponse.success(id: 'req-ack-empty', result: const {'ok': true});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-ack-empty',
        'result': const {'ok': true},
      };
      await prepareValidResponse(response, prepared);

      when(
        () => socket.emitWithAck(
          any<String>(),
          any<dynamic>(),
          ack: any(named: 'ack'),
        ),
      ).thenAnswer((invocation) {
        final ack = invocation.namedArguments[#ack] as Function?;
        // Simulate socket_io_client onack with data: [] → Function.apply(ack, []).
        Function.apply(ack!, []);
      });

      final coordinator = createCoordinator();
      await coordinator.emit(response);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(metrics.rpcResponseAckDeliveredCount, 1);
      expect(metrics.rpcResponseAckRetryCount, 0);
      expect(metrics.rpcResponseAckFallbackWithoutAckCount, 0);
      verifyNever(() => socket.emit('rpc:response', any<dynamic>()));
      verifyNever(() => socket.timeout(any<int>()));
      verifyNever(() => socket.emitWithAckAsync(any<String>(), any<dynamic>()));
    });

    test('times out ACK wait and falls back to emit without ack', () async {
      deliveryGuaranteesEnabled = true;
      final response = RpcResponse.success(id: 'req-ack-timeout', result: const {'ok': true});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-ack-timeout',
        'result': const {'ok': true},
      };
      await prepareValidResponse(response, prepared);

      when(
        () => socket.emitWithAck(
          any<String>(),
          any<dynamic>(),
          ack: any(named: 'ack'),
        ),
      ).thenReturn(null);

      final coordinator = createCoordinator(
        responseAckTimeout: const Duration(milliseconds: 20),
      );
      await coordinator.emit(response);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(metrics.rpcResponseAckFallbackWithoutAckCount, 1);
      expect(metrics.rpcResponseAckRetryCount, greaterThan(0));
      expect(metrics.rpcResponseAckDeliveredCount, 0);
      verify(() => socket.emit('rpc:response', prepared)).called(1);
    });

    test('aborts pending ACK when connect generation changes', () async {
      deliveryGuaranteesEnabled = true;
      var generation = 1;
      final response = RpcResponse.success(id: 'req-ack-abort', result: const {'ok': true});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-ack-abort',
        'result': const {'ok': true},
      };
      await prepareValidResponse(response, prepared);

      final ackStarted = Completer<void>();
      when(
        () => socket.emitWithAck(
          any<String>(),
          any<dynamic>(),
          ack: any(named: 'ack'),
        ),
      ).thenAnswer((_) {
        if (!ackStarted.isCompleted) {
          ackStarted.complete();
        }
      });

      final coordinator = createCoordinator(
        connectGenerationProvider: () => generation,
        responseAckTimeout: const Duration(seconds: 5),
      );
      await coordinator.emit(response);
      await ackStarted.future;
      generation = 2;
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(metrics.rpcResponseAckAbortedConnectionChangeCount, 1);
      expect(metrics.rpcResponseAckRetryCount, 0);
      expect(metrics.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(metrics.rpcResponseAckDeliveredCount, 0);
      verifyNever(() => socket.emit('rpc:response', any<dynamic>()));
    });

    test('skips Socket.IO ACK for sql.execute responses', () async {
      deliveryGuaranteesEnabled = true;
      final response = RpcResponse.success(id: 'req-sql', result: const {'rows': <Object?>[]});
      final prepared = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-sql',
        'result': const {'rows': <Object?>[]},
      };
      await prepareValidResponse(response, prepared);

      final coordinator = createCoordinator();
      await coordinator.emit(
        response,
        methodsById: const <Object?, String>{'req-sql': 'sql.execute'},
      );

      verify(() => socket.emit('rpc:response', prepared)).called(1);
      verifyNever(
        () => socket.emitWithAck(
          any<String>(),
          any<dynamic>(),
          ack: any(named: 'ack'),
        ),
      );
      expect(metrics.rpcResponseAckSkippedSqlExecuteCount, 1);
    });
  });
}
