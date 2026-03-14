import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

class MockSocketDataSource extends Mock implements SocketDataSource {}

class MockProtocolNegotiator extends Mock implements ProtocolNegotiator {}

class MockRpcMethodDispatcher extends Mock implements RpcMethodDispatcher {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockSocket extends Mock implements io.Socket {}

class MockRpcStreamEmitter extends Mock implements IRpcStreamEmitter {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
      ),
    );
    registerFallbackValue(ProtocolCapabilities.defaultCapabilities());
    registerFallbackValue(const TransportLimits());
    registerFallbackValue(MockRpcStreamEmitter());
  });

  group('SocketIOTransportClientV2', () {
    late MockSocketDataSource mockDataSource;
    late MockProtocolNegotiator mockNegotiator;
    late MockRpcMethodDispatcher mockDispatcher;
    late MockFeatureFlags mockFeatureFlags;
    late MockSocket mockSocket;
    late SocketIOTransportClientV2 client;
    late Map<String, Function> handlers;
    late List<({String event, dynamic data})> emitted;

    void emitEvent(String event, [dynamic data]) {
      final handler = handlers[event];
      if (handler != null) {
        Function.apply(handler, [data]);
      }
    }

    setUp(() {
      mockDataSource = MockSocketDataSource();
      mockNegotiator = MockProtocolNegotiator();
      mockDispatcher = MockRpcMethodDispatcher();
      mockFeatureFlags = MockFeatureFlags();
      mockSocket = MockSocket();
      handlers = <String, Function>{};
      emitted = <({String event, dynamic data})>[];

      when(
        () => mockDataSource.createSocket(
          any(),
          authToken: any(named: 'authToken'),
        ),
      ).thenReturn(mockSocket);
      when(() => mockSocket.connected).thenReturn(true);
      when(() => mockSocket.on(any<String>(), any())).thenAnswer((invocation) {
        handlers[invocation.positionalArguments[0] as String] =
            invocation.positionalArguments[1] as Function;
        return () {};
      });
      when(() => mockSocket.emit(any<String>(), any<dynamic>())).thenAnswer((
        invocation,
      ) {
        emitted.add((
          event: invocation.positionalArguments[0] as String,
          data: invocation.positionalArguments[1],
        ));
      });
      when(() => mockSocket.connect()).thenReturn(mockSocket);
      when(() => mockSocket.disconnect()).thenReturn(mockSocket);
      when(() => mockSocket.dispose()).thenReturn(null);

      when(() => mockFeatureFlags.enableSocketBackpressure).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketSchemaValidation,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketDeliveryGuarantees,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketNotificationsContract,
      ).thenReturn(true);
      when(
        () => mockFeatureFlags.enableSocketStreamingChunks,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketBatchStrictValidation,
      ).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketApiVersionMeta).thenReturn(false);
      when(() => mockFeatureFlags.enablePayloadSigning).thenReturn(false);
      when(
        () => mockFeatureFlags.enableClientTokenAuthorization,
      ).thenReturn(false);

      when(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer(
        (_) async => RpcResponse.success(
          id: 'req-1',
          result: <String, dynamic>{'ok': true},
        ),
      );

      client = SocketIOTransportClientV2(
        dataSource: mockDataSource,
        negotiator: mockNegotiator,
        rpcDispatcher: mockDispatcher,
        featureFlags: mockFeatureFlags,
      );
    });

    test('should emit agent:register on connect with capabilities', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');

      final result = await connectFuture;

      expect(result.isSuccess(), isTrue);
      expect(emitted.any((item) => item.event == 'agent:register'), isTrue);
      final registerPayload =
          emitted.firstWhere((item) => item.event == 'agent:register').data
              as Map<String, dynamic>;
      expect(registerPayload['agentId'], 'agent-1');
      expect(registerPayload['capabilities'], isA<Map<String, dynamic>>());
    });

    test(
      'should process notification without rpc response or request ack',
      () async {
        when(
          () => mockFeatureFlags.enableSocketDeliveryGuarantees,
        ).thenReturn(true);
        when(
          () => mockDispatcher.dispatch(
            any(),
            any(),
            clientToken: any(named: 'clientToken'),
            streamEmitter: any(named: 'streamEmitter'),
            limits: any(named: 'limits'),
            negotiatedExtensions: any(named: 'negotiatedExtensions'),
          ),
        ).thenAnswer(
          (_) async => RpcResponse.success(
            id: null,
            result: <String, dynamic>{'ok': true},
          ),
        );

        final connectFuture = client.connect('https://hub.test', 'agent-1');
        emitEvent('connect');
        await connectFuture;
        emitted.clear();

        emitEvent('rpc:request', <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'params': {'sql': "INSERT INTO logs (msg) VALUES ('ok')"},
        });

        await Future<void>.delayed(Duration.zero);

        verify(
          () => mockDispatcher.dispatch(
            any(
              that: isA<RpcRequest>().having(
                (request) => request.id,
                'id',
                isNull,
              ),
            ),
            any(),
            clientToken: any(named: 'clientToken'),
            streamEmitter: any(named: 'streamEmitter'),
            limits: any(named: 'limits'),
            negotiatedExtensions: any(named: 'negotiatedExtensions'),
          ),
        ).called(1);
        expect(emitted.any((item) => item.event == 'rpc:response'), isFalse);
        expect(emitted.any((item) => item.event == 'rpc:request_ack'), isFalse);
      },
    );

    test('should reject payloads above negotiated limit', () async {
      when(
        () => mockNegotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
          preferJsonRpcV2: any(named: 'preferJsonRpcV2'),
        ),
      ).thenReturn(
        const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
          effectiveLimits: TransportLimits(maxPayloadBytes: 100),
        ),
      );
      when(
        () => mockFeatureFlags.enableSocketSchemaValidation,
      ).thenReturn(true);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      emitEvent('agent:capabilities', {
        'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
      });
      emitted.clear();

      emitEvent('rpc:request', <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': 'req-big',
        'params': {'sql': 'SELECT ${'x' * 300}'},
      });

      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      );
      final responsePayload =
          emitted.firstWhere((item) => item.event == 'rpc:response').data
              as Map<String, dynamic>;
      final error = responsePayload['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.invalidPayload);
    });

    test(
      'should reject id null when compatibility is not negotiated',
      () async {
        when(
          () => mockNegotiator.negotiate(
            agentCapabilities: any(named: 'agentCapabilities'),
            serverCapabilities: any(named: 'serverCapabilities'),
            preferJsonRpcV2: any(named: 'preferJsonRpcV2'),
          ),
        ).thenReturn(
          const ProtocolConfig(
            protocol: 'jsonrpc-v2',
            encoding: 'json',
            compression: 'none',
            negotiatedExtensions: {
              'notificationNullIdCompatibility': false,
            },
          ),
        );

        final connectFuture = client.connect('https://hub.test', 'agent-1');
        emitEvent('connect');
        await connectFuture;
        emitEvent('agent:capabilities', {
          'capabilities': const ProtocolCapabilities(
            protocols: ['jsonrpc-v2'],
            encodings: ['json'],
            compressions: ['none'],
            extensions: {'notificationNullIdCompatibility': false},
          ).toJson(),
        });
        emitted.clear();

        emitEvent('rpc:request', <String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': null,
          'params': {'sql': 'SELECT 1'},
        });

        await Future<void>.delayed(Duration.zero);

        verifyNever(
          () => mockDispatcher.dispatch(
            any(),
            any(),
            clientToken: any(named: 'clientToken'),
            streamEmitter: any(named: 'streamEmitter'),
            limits: any(named: 'limits'),
            negotiatedExtensions: any(named: 'negotiatedExtensions'),
          ),
        );
        final responsePayload =
            emitted.firstWhere((item) => item.event == 'rpc:response').data
                as Map<String, dynamic>;
        final error = responsePayload['error'] as Map<String, dynamic>;
        expect(error['code'], RpcErrorCode.invalidRequest);
      },
    );

    test('should respond to rpc.discover with OpenRPC document', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      emitted.clear();

      emitEvent('rpc:request', <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'rpc.discover',
        'id': 'req-discover',
      });

      await Future<void>.delayed(Duration.zero);

      verifyNever(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      );
      final responsePayload =
          emitted.firstWhere((item) => item.event == 'rpc:response').data
              as Map<String, dynamic>;
      expect(
        (responsePayload['result'] as Map<String, dynamic>)['openrpc'],
        '1.3.2',
      );
    });
  });
}
