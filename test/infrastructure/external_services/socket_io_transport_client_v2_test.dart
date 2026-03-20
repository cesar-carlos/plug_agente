import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

class MockSocketDataSource extends Mock implements SocketDataSource {}

class MockProtocolNegotiator extends Mock implements ProtocolNegotiator {}

class MockRpcMethodDispatcher extends Mock implements RpcMethodDispatcher {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockSocket extends Mock implements io.Socket {}

class MockRpcStreamEmitter extends Mock implements IRpcStreamEmitter {}

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock
    implements QueryNormalizerService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

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
    registerFallbackValue(
      QueryRequest(
        id: 'test',
        agentId: 'test',
        query: 'SELECT * FROM test',
        timestamp: DateTime.now(),
      ),
    );
    registerFallbackValue(
      QueryResponse(
        id: 'exec-1',
        requestId: 'req-1',
        agentId: 'agent-1',
        data: const [],
        timestamp: DateTime.now(),
      ),
    );
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

    const defaultNegotiatedConfig = ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'gzip',
      signatureAlgorithms: ['hmac-sha256'],
      negotiatedExtensions: {
        'binaryPayload': true,
        'transportFrame': 'payload-frame/1.0',
        'notificationNullIdCompatibility': true,
        'signatureRequired': false,
        'signatureAlgorithms': ['hmac-sha256'],
      },
    );

    void emitEvent(String event, [dynamic data]) {
      final handler = handlers[event];
      if (handler != null) {
        Function.apply(handler, [data]);
      }
    }

    dynamic decodeWirePayload(dynamic payload) {
      if (payload is! Map<String, dynamic> ||
          !payload.containsKey('schemaVersion')) {
        return payload;
      }
      final frame = PayloadFrame.fromJson(payload);
      final decoded = TransportPipeline(
        encoding: frame.enc,
        compression: frame.cmp,
        schemaVersion: frame.schemaVersion,
      ).receiveProcess(frame);
      expect(decoded.isSuccess(), isTrue);
      return decoded.getOrThrow();
    }

    Map<String, dynamic> encodeWirePayload(dynamic payload) {
      final frame = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
      ).prepareSend(payload).getOrThrow();
      return frame.toJson();
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
      when(
        () => mockDispatcher.cancelActiveStreamOnDisconnect(),
      ).thenAnswer((_) async {});
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
      when(() => mockFeatureFlags.enableBinaryPayload).thenReturn(true);
      when(() => mockFeatureFlags.enableCompression).thenReturn(true);
      when(() => mockFeatureFlags.compressionThreshold).thenReturn(1024);
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
        () => mockFeatureFlags.enableSocketIdempotency,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketTimeoutByStage,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketStreamingFromDb,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketCancelMethod,
      ).thenReturn(false);
      when(
        () => mockNegotiator.negotiate(
          agentCapabilities: any(named: 'agentCapabilities'),
          serverCapabilities: any(named: 'serverCapabilities'),
          preferJsonRpcV2: any(named: 'preferJsonRpcV2'),
        ),
      ).thenReturn(defaultNegotiatedConfig);

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
          decodeWirePayload(
                emitted
                    .firstWhere((item) => item.event == 'agent:register')
                    .data,
              )
              as Map<String, dynamic>;
      expect(registerPayload['agentId'], 'agent-1');
      expect(registerPayload['capabilities'], isA<Map<String, dynamic>>());
      expect(
        (registerPayload['capabilities'] as Map<String, dynamic>)['extensions'],
        isA<Map<String, dynamic>>(),
      );
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

        emitEvent(
          'rpc:request',
          encodeWirePayload(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'params': {'sql': "INSERT INTO logs (msg) VALUES ('ok')"},
          }),
        );

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
          signatureAlgorithms: ['hmac-sha256'],
          effectiveLimits: TransportLimits(maxPayloadBytes: 400),
          negotiatedExtensions: {
            'binaryPayload': true,
            'transportFrame': 'payload-frame/1.0',
            'notificationNullIdCompatibility': true,
            'signatureRequired': false,
            'signatureAlgorithms': ['hmac-sha256'],
          },
        ),
      );
      when(
        () => mockFeatureFlags.enableSocketSchemaValidation,
      ).thenReturn(true);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-big',
          'params': {'sql': 'SELECT ${'x' * 600}'},
        }),
      );

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
          decodeWirePayload(
                emitted.firstWhere((item) => item.event == 'rpc:response').data,
              )
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
            compression: 'gzip',
            signatureAlgorithms: ['hmac-sha256'],
            negotiatedExtensions: {
              'binaryPayload': true,
              'transportFrame': 'payload-frame/1.0',
              'notificationNullIdCompatibility': false,
              'signatureRequired': false,
              'signatureAlgorithms': ['hmac-sha256'],
            },
          ),
        );

        final connectFuture = client.connect('https://hub.test', 'agent-1');
        emitEvent('connect');
        await connectFuture;
        emitEvent(
          'agent:capabilities',
          encodeWirePayload({
            'capabilities': const ProtocolCapabilities(
              protocols: ['jsonrpc-v2'],
              encodings: ['json'],
              compressions: ['none'],
              extensions: {
                'binaryPayload': true,
                'transportFrame': 'payload-frame/1.0',
                'notificationNullIdCompatibility': false,
                'signatureRequired': false,
                'signatureAlgorithms': ['hmac-sha256'],
              },
            ).toJson(),
          }),
        );
        emitted.clear();

        emitEvent(
          'rpc:request',
          encodeWirePayload(<String, dynamic>{
            'jsonrpc': '2.0',
            'method': 'sql.execute',
            'id': null,
            'params': {'sql': 'SELECT 1'},
          }),
        );

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
            decodeWirePayload(
                  emitted
                      .firstWhere((item) => item.event == 'rpc:response')
                      .data,
                )
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

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'rpc.discover',
          'id': 'req-discover',
        }),
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

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
          decodeWirePayload(
                emitted.firstWhere((item) => item.event == 'rpc:response').data,
              )
              as Map<String, dynamic>;
      expect(
        (responsePayload['result'] as Map<String, dynamic>)['openrpc'],
        '1.3.2',
      );
    });

    test(
      'should disconnect when capabilities do not support mandatory binary transport',
      () async {
        var reconnectionRequested = false;
        client.setOnReconnectionNeeded(() {
          reconnectionRequested = true;
        });

        final connectFuture = client.connect('https://hub.test', 'agent-1');
        emitEvent('connect');
        await connectFuture;

        emitEvent(
          'agent:capabilities',
          encodeWirePayload({
            'capabilities': ProtocolCapabilities.defaultCapabilities(
              binaryPayload: false,
            ).toJson(),
          }),
        );

        verify(() => mockSocket.disconnect()).called(greaterThanOrEqualTo(1));
        expect(reconnectionRequested, isTrue);
      },
    );

    test(
      'should disconnect when mandatory transport signature is required and missing',
      () async {
        when(() => mockFeatureFlags.enablePayloadSigning).thenReturn(true);
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
            compression: 'gzip',
            signatureRequired: true,
            signatureAlgorithms: ['hmac-sha256'],
            negotiatedExtensions: {
              'binaryPayload': true,
              'transportFrame': 'payload-frame/1.0',
              'notificationNullIdCompatibility': true,
              'signatureRequired': true,
              'signatureAlgorithms': ['hmac-sha256'],
            },
          ),
        );

        client = SocketIOTransportClientV2(
          dataSource: mockDataSource,
          negotiator: mockNegotiator,
          rpcDispatcher: mockDispatcher,
          featureFlags: mockFeatureFlags,
          payloadSigner: PayloadSigner(keys: {'kid-1': 'secret'}),
        );

        var reconnectionRequested = false;
        client.setOnReconnectionNeeded(() {
          reconnectionRequested = true;
        });

        final connectFuture = client.connect('https://hub.test', 'agent-1');
        emitEvent('connect');
        await connectFuture;

        emitEvent(
          'agent:capabilities',
          encodeWirePayload({
            'capabilities': ProtocolCapabilities.defaultCapabilities(
              signatureRequired: true,
            ).toJson(),
          }),
        );

        verify(() => mockSocket.disconnect()).called(greaterThanOrEqualTo(1));
        expect(reconnectionRequested, isTrue);
      },
    );

    test('should reject rpc request that is not a PayloadFrame', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      emitted.clear();

      emitEvent('rpc:request', <String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'sql.execute',
        'id': 'req-invalid',
        'params': {'sql': 'SELECT 1'},
      });

      await Future<void>.delayed(Duration.zero);

      final responsePayload =
          decodeWirePayload(
                emitted.firstWhere((item) => item.event == 'rpc:response').data,
              )
              as Map<String, dynamic>;
      expect(
        (responsePayload['error'] as Map<String, dynamic>)['code'],
        RpcErrorCode.invalidPayload,
      );
    });

    group('execution_mode', () {
      test(
        'should pass execution_mode preserve to dispatcher and return sql_handling_mode',
        () async {
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
              result: <String, dynamic>{
                'execution_id': 'exec-1',
                'sql_handling_mode': 'preserve',
                'max_rows_handling': 'response_truncation',
                'effective_max_rows': 50000,
                'rows': <Map<String, dynamic>>[],
                'row_count': 0,
              },
            ),
          );

          final connectFuture = client.connect('https://hub.test', 'agent-1');
          emitEvent('connect');
          await connectFuture;
          emitted.clear();

          emitEvent(
            'rpc:request',
            encodeWirePayload(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'sql.execute',
              'id': 'req-1',
              'params': {
                'sql': 'SELECT * FROM t',
                'options': {'execution_mode': 'preserve'},
              },
            }),
          );

          await Future<void>.delayed(Duration.zero);

          verify(
            () => mockDispatcher.dispatch(
              any(
                that: isA<RpcRequest>().having(
                  (r) {
                    final params = r.params as Map<String, dynamic>?;
                    final options = params?['options'] as Map<String, dynamic>?;
                    return options?['execution_mode'];
                  },
                  'params.options.execution_mode',
                  'preserve',
                ),
              ),
              any(),
              clientToken: any(named: 'clientToken'),
              streamEmitter: any(named: 'streamEmitter'),
              limits: any(named: 'limits'),
              negotiatedExtensions: any(named: 'negotiatedExtensions'),
            ),
          ).called(1);

          final responsePayload =
              decodeWirePayload(
                    emitted
                        .firstWhere((item) => item.event == 'rpc:response')
                        .data,
                  )
                  as Map<String, dynamic>;
          final result = responsePayload['result'] as Map<String, dynamic>?;
          expect(result, isNotNull);
          final mode = result!['sql_handling_mode'] as String?;
          expect(mode, 'preserve');
        },
      );

      test(
        'should pass preserve_sql alias to dispatcher and return sql_handling_mode',
        () async {
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
              result: <String, dynamic>{
                'execution_id': 'exec-1',
                'sql_handling_mode': 'preserve',
                'max_rows_handling': 'response_truncation',
                'effective_max_rows': 50000,
                'rows': <Map<String, dynamic>>[],
                'row_count': 0,
              },
            ),
          );

          final connectFuture = client.connect('https://hub.test', 'agent-1');
          emitEvent('connect');
          await connectFuture;
          emitted.clear();

          emitEvent(
            'rpc:request',
            encodeWirePayload(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'sql.execute',
              'id': 'req-1',
              'params': {
                'sql': 'SELECT * FROM t',
                'options': {'preserve_sql': true},
              },
            }),
          );

          await Future<void>.delayed(Duration.zero);

          verify(
            () => mockDispatcher.dispatch(
              any(
                that: isA<RpcRequest>().having(
                  (r) {
                    final params = r.params as Map<String, dynamic>?;
                    final options = params?['options'] as Map<String, dynamic>?;
                    return options?['preserve_sql'];
                  },
                  'params.options.preserve_sql',
                  true,
                ),
              ),
              any(),
              clientToken: any(named: 'clientToken'),
              streamEmitter: any(named: 'streamEmitter'),
              limits: any(named: 'limits'),
              negotiatedExtensions: any(named: 'negotiatedExtensions'),
            ),
          ).called(1);

          final responsePayload =
              decodeWirePayload(
                    emitted
                        .firstWhere((item) => item.event == 'rpc:response')
                        .data,
                  )
                  as Map<String, dynamic>;
          final result = responsePayload['result'] as Map<String, dynamic>?;
          expect(result, isNotNull);
          final mode = result!['sql_handling_mode'] as String?;
          expect(mode, 'preserve');
        },
      );
    });

    group('integration with real dispatcher', () {
      test(
        'should process execution_mode preserve through transport and dispatcher',
        () async {
          final mockGateway = MockDatabaseGateway();
          final mockNormalizer = MockQueryNormalizerService();
          final mockAuthorize = MockAuthorizeSqlOperation();

          final queryResponse = QueryResponse(
            id: 'exec-1',
            requestId: 'req-1',
            agentId: 'agent-1',
            data: const [
              {'id': 1},
            ],
            timestamp: DateTime.now(),
          );
          when(
            () => mockGateway.executeQuery(any()),
          ).thenAnswer((_) async => Success(queryResponse));
          when(
            () => mockNormalizer.normalize(any()),
          ).thenAnswer((_) async => queryResponse);

          final realDispatcher = RpcMethodDispatcher(
            databaseGateway: mockGateway,
            normalizerService: mockNormalizer,
            uuid: const Uuid(),
            authorizeSqlOperation: mockAuthorize,
            featureFlags: mockFeatureFlags,
          );

          final integrationClient = SocketIOTransportClientV2(
            dataSource: mockDataSource,
            negotiator: mockNegotiator,
            rpcDispatcher: realDispatcher,
            featureFlags: mockFeatureFlags,
          );

          final connectFuture = integrationClient.connect(
            'https://hub.test',
            'agent-1',
          );
          emitEvent('connect');
          await connectFuture;
          emitted.clear();

          emitEvent(
            'rpc:request',
            encodeWirePayload(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'sql.execute',
              'id': 'req-1',
              'params': {
                'sql': 'SELECT * FROM t',
                'options': {'execution_mode': 'preserve'},
              },
            }),
          );

          await Future<void>.delayed(const Duration(milliseconds: 100));

          final responseItems = emitted
              .where((item) => item.event == 'rpc:response')
              .toList();
          expect(responseItems, isNotEmpty);
          final responsePayload =
              decodeWirePayload(responseItems.first.data)
                  as Map<String, dynamic>;
          final result = responsePayload['result'] as Map<String, dynamic>?;
          expect(result, isNotNull);
          expect(result!['sql_handling_mode'], 'preserve');
          expect(result['effective_max_rows'], isNotNull);
        },
      );
    });
  });
}
