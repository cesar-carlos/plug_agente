import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_runtime_state_guard.dart';
import 'package:plug_agente/application/actions/agent_actions_remote_capability_provider.dart';
import 'package:plug_agente/application/actions/elevated_action_runner_readiness_service.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_batch_constants.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_local_runner.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_protocol_negotiator.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/domain/value_objects/hub_lifecycle_notification.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart' as socket_io_manager;
import 'package:uuid/uuid.dart';

import '../../helpers/rpc_method_dispatcher_test_support.dart';

NetworkFailure requireNetworkFailure(Result<void> result) {
  expect(result.isError(), isTrue);
  final Object? error = result.exceptionOrNull();
  expect(error, isA<NetworkFailure>(), reason: 'Expected NetworkFailure, got $error');
  return error! as NetworkFailure;
}

class MockSocketDataSource extends Mock implements SocketDataSource {}

class MockProtocolNegotiator extends Mock implements IProtocolNegotiator {}

class MockRpcRequestDispatcher extends Mock implements IRpcRequestDispatcher {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockAgentActionLocalRunner extends Mock implements AgentActionLocalRunner {}

class MockSocket extends Mock implements io.Socket {}

class MockManager extends Mock implements socket_io_manager.Manager {}

class MockRpcStreamEmitter extends Mock implements IRpcStreamEmitter {}

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

final ClientTokenGetPolicyRateLimiter _transportTestNoopGetPolicyRateLimiter = ClientTokenGetPolicyRateLimiter(
  maxCallsPerMinute: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    late MockRpcRequestDispatcher mockDispatcher;
    late MockFeatureFlags mockFeatureFlags;
    late MockSocket mockSocket;
    late MockManager mockManager;
    late ProtocolMetricsCollector metricsCollector;
    late MetricsCollector rpcMetricsCollector;
    late SocketIOTransportClientV2 client;
    late Map<String, Function> handlers;
    late Map<String, Function> managerHandlers;
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

    void emitManagerEvent(String event, [dynamic data]) {
      final handler = managerHandlers[event];
      if (handler != null) {
        Function.apply(handler, [data]);
      }
    }

    dynamic decodeWirePayload(dynamic payload) {
      if (payload is! Map<String, dynamic> || !payload.containsKey('schemaVersion')) {
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

    /// Drives `agent:capabilities` so subsequent `rpc:request` events are not
    /// rejected by the protocol_not_ready guard. Assumes `connect` was already
    /// emitted by the test.
    Future<void> negotiateProtocol({Map<String, dynamic>? capabilities}) async {
      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': capabilities ?? ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );
      await Future<void>.delayed(Duration.zero);
    }

    Future<JsonSchemaContractValidator> buildJsonSchemaValidator() async {
      final loader = TransportSchemaLoader();
      await loader.loadAll();
      return JsonSchemaContractValidator(loader: loader);
    }

    setUp(() {
      mockDataSource = MockSocketDataSource();
      mockNegotiator = MockProtocolNegotiator();
      mockDispatcher = MockRpcRequestDispatcher();
      mockFeatureFlags = MockFeatureFlags();
      mockSocket = MockSocket();
      mockManager = MockManager();
      metricsCollector = ProtocolMetricsCollector();
      rpcMetricsCollector = MetricsCollector();
      handlers = <String, Function>{};
      managerHandlers = <String, Function>{};
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
      when(() => mockSocket.io).thenReturn(mockManager);
      when(() => mockSocket.on(any<String>(), any())).thenAnswer((invocation) {
        handlers[invocation.positionalArguments[0] as String] = invocation.positionalArguments[1] as Function;
        return () {};
      });
      when(() => mockManager.on(any<String>(), any())).thenAnswer((invocation) {
        final event = invocation.positionalArguments[0] as String;
        managerHandlers[event] = invocation.positionalArguments[1] as Function;
        return () {
          managerHandlers.remove(event);
        };
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
      when(() => mockFeatureFlags.outboundCompressionMode).thenReturn(
        OutboundCompressionMode.gzip,
      );
      when(() => mockFeatureFlags.compressionThreshold).thenReturn(1024);
      when(
        () => mockFeatureFlags.enableSocketSchemaValidation,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableSocketOutgoingContractValidation,
      ).thenReturn(true);
      when(
        () => mockFeatureFlags.enableSocketSummarizeLargePayloadLogs,
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
      when(() => mockFeatureFlags.requireIncomingPayloadSignatures).thenReturn(false);
      when(
        () => mockFeatureFlags.enableClientTokenAuthorization,
      ).thenReturn(false);
      when(
        () => mockFeatureFlags.enableClientTokenPolicyIntrospection,
      ).thenReturn(true);
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
      when(() => mockFeatureFlags.enableAgentActions).thenReturn(true);
      when(() => mockFeatureFlags.enableRemoteAgentActions).thenReturn(false);
      when(() => mockFeatureFlags.enableRemoteAdHocAgentActions).thenReturn(false);
      when(() => mockFeatureFlags.enableElevatedAgentActions).thenReturn(false);
      when(() => mockFeatureFlags.enableAgentActionsMaintenanceMode).thenReturn(false);
      when(() => mockFeatureFlags.enableAgentActionsMaintenanceStrictMode).thenReturn(false);
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(false);
      when(() => mockFeatureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(false);
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
        options: SocketIOTransportClientV2Options(
          protocolMetricsCollector: metricsCollector,
          metricsCollector: rpcMetricsCollector,
        ),
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
                emitted.firstWhere((item) => item.event == 'agent:register').data,
              )
              as Map<String, dynamic>;
      expect(registerPayload['agentId'], 'agent-1');
      expect(registerPayload['capabilities'], isA<Map<String, dynamic>>());
      expect(
        (registerPayload['capabilities'] as Map<String, dynamic>)['extensions'],
        isA<Map<String, dynamic>>(),
      );
    });

    test('should advertise agent action runtime status when remote actions are enabled', () async {
      when(() => mockFeatureFlags.enableAgentActions).thenReturn(true);
      when(() => mockFeatureFlags.enableRemoteAgentActions).thenReturn(true);

      final commandLineRunner = MockAgentActionLocalRunner();
      when(() => commandLineRunner.type).thenReturn(AgentActionType.commandLine);
      final developerRunner = MockAgentActionLocalRunner();
      when(() => developerRunner.type).thenReturn(AgentActionType.developer);
      final runnerRegistry = AgentActionLocalRunnerRegistry([
        commandLineRunner,
        developerRunner,
      ]);

      final runtimeStateGuard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');
      final capabilityProvider = AgentActionsRemoteCapabilityProvider(
        runtimeStateGuard: runtimeStateGuard,
        elevatedRunnerReadiness: ElevatedActionRunnerReadinessService(),
      );
      client = SocketIOTransportClientV2(
        dataSource: mockDataSource,
        negotiator: mockNegotiator,
        rpcDispatcher: mockDispatcher,
        featureFlags: mockFeatureFlags,
        options: SocketIOTransportClientV2Options(
          protocolMetricsCollector: metricsCollector,
          metricsCollector: rpcMetricsCollector,
          agentActionsRemoteCapabilityProvider: capabilityProvider,
          agentActionLocalRunnerRegistry: runnerRegistry,
        ),
      );

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      final result = await connectFuture;

      expect(result.isSuccess(), isTrue);
      final registerPayload =
          decodeWirePayload(
                emitted.firstWhere((item) => item.event == 'agent:register').data,
              )
              as Map<String, dynamic>;
      final capabilities = registerPayload['capabilities'] as Map<String, dynamic>;
      final extensions = capabilities['extensions'] as Map<String, dynamic>;
      final agentActions = extensions['agentActions'] as Map<String, dynamic>;

      expect(agentActions['enabled'], isTrue);
      expect(agentActions['status'], 'draining');
      expect(agentActions['maintenanceMode'], isFalse);
      expect(agentActions['maintenanceStrictMode'], isFalse);
      expect(agentActions['remoteAdHoc'], isFalse);
      expect(agentActions['elevatedAllowed'], isFalse);
      expect(agentActions['supportsElevated'], isFalse);
      expect(agentActions['requiresIdempotencyKey'], isTrue);
      expect(agentActions['supportsRun'], isTrue);
      expect(agentActions['supportsValidateRun'], isTrue);
      expect(agentActions['supportsDryRun'], isTrue);
      expect(agentActions['supportsContext'], isFalse);
      expect(agentActions['supportsOutputPaging'], isTrue);
      expect(agentActions['supportsCancel'], isTrue);
      expect(agentActions['supportsGetExecution'], isTrue);
      expect(agentActions['methods'], AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered);
      expect(agentActions['supportedMethods'], AgentActionRpcConstants.remotePublishedRpcMethodNamesOrdered);
      expect(agentActions['authorizationScopes'], AgentActionRpcConstants.remotePublishedAuthorizationScopesOrdered);
      expect(agentActions['supportedTypes'], ['commandLine', 'developer']);
      expect(agentActions['version'], 1);
      expect(agentActions['unavailableTypes'], isEmpty);
      expect(
        agentActions['defaultQueueLimits'],
        AgentActionRpcConstants.remoteAgentActionsDefaultQueueLimitsCapability,
      );
      expect(
        agentActions['limits'],
        AgentActionRpcConstants.remoteAgentActionsLimitsCapability,
      );
      expect(
        agentActions['batchPolicy'],
        AgentActionRpcConstants.remoteAgentActionsBatchPolicyCapability,
      );
    });

    test('should request fresh reconnect after server-side disconnect', () async {
      var reconnectRequests = 0;
      client.setOnReconnectionNeeded(() => reconnectRequests++);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      emitEvent('disconnect', 'io server disconnect');
      await Future<void>.delayed(Duration.zero);

      expect(reconnectRequests, 1);
    });

    test('should NOT call cancelActiveStreamOnDisconnect inside _handleDisconnect (H3)', () async {
      // After removing the duplicate cancel in _handleDisconnect, a transport
      // disconnect event alone must NOT call cancelActiveStreamOnDisconnect;
      // only _closeSocket (called from connect/disconnect) owns that call.
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      // Reset interactions so the call from connect()._closeSocket is not counted.
      clearInteractions(mockDispatcher);

      emitEvent('disconnect', 'transport close');
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => mockDispatcher.cancelActiveStreamOnDisconnect());
    });

    test('should include startedAt in rpc:response when sendResponse provides it (H1)', () async {
      final finishedAt = DateTime.utc(2026, 5, 1, 12);
      final startedAt = DateTime.utc(2026, 5, 1, 11, 59, 55);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();

      await client.sendResponse(
        QueryResponse(
          id: 'exec-1',
          requestId: 'req-1',
          agentId: 'agent-1',
          data: const [],
          timestamp: finishedAt,
          startedAt: startedAt,
        ),
      );

      final responseItems = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responseItems, isNotEmpty);
      expect((responseItems.first.data as Map<String, dynamic>)['payload'], isA<ByteBuffer>());
      final payload = decodeWirePayload(responseItems.first.data) as Map<String, dynamic>;
      final result = payload['result'] as Map<String, dynamic>;
      expect(result['started_at'], startedAt.toIso8601String());
      expect(result['finished_at'], finishedAt.toIso8601String());
      expect(result['started_at'] != result['finished_at'], isTrue);
    });

    test('should omit materialized rpc:response rows from socket log callback', () async {
      final logged = <({String direction, String event, dynamic data})>[];
      client.setMessageCallback(
        (String direction, String event, dynamic data) {
          logged.add((direction: direction, event: event, data: data));
        },
      );

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();

      await client.sendResponse(
        QueryResponse(
          id: 'exec-1',
          requestId: 'req-codcliente-001',
          agentId: 'agent-1',
          data: const [
            {'CodCliente': 1, 'raw_payload': 'raw-row-should-not-reach-log-callback'},
          ],
          timestamp: DateTime.utc(2026, 5, 1, 12),
          affectedRows: 1,
          columnMetadata: const [
            {'name': 'CodCliente', 'type': 'int'},
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final responseLog = logged.firstWhere((item) => item.event == 'rpc:response');
      expect(responseLog.data.toString(), isNot(contains('raw-row-should-not-reach-log-callback')));
      final payload = responseLog.data as Map<String, dynamic>;
      final result = payload['result'] as Map<String, dynamic>;
      expect(result['row_count'], 1);
      expect(result['affected_rows'], 1);
      expect(result['rows'], 'omitted_from_socket_log');
      expect(result['column_metadata_count'], 1);
    });

    test('should omit sql.executeBatch item rows from socket log callback', () async {
      final logged = <({String direction, String event, dynamic data})>[];
      client.setMessageCallback(
        (String direction, String event, dynamic data) {
          logged.add((direction: direction, event: event, data: data));
        },
      );

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();

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
          id: 'batch-1',
          result: <String, dynamic>{
            'execution_id': 'exec-batch-1',
            'items': [
              {
                'index': 0,
                'ok': true,
                'rows': [
                  {'CodCliente': 1, 'raw_payload': 'raw-batch-row-should-not-reach-log-callback'},
                ],
                'row_count': 1,
                'column_metadata': const [
                  {'name': 'CodCliente'},
                ],
              },
            ],
            'total_commands': 1,
            'successful_commands': 1,
            'failed_commands': 0,
          },
        ),
      );

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'batch-1',
          'method': 'sql.executeBatch',
          'params': {
            'commands': const [
              {'sql': 'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente'},
            ],
            'client_token': 'token',
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final responseLog = logged.firstWhere((item) => item.event == 'rpc:response');
      expect(responseLog.data.toString(), isNot(contains('raw-batch-row-should-not-reach-log-callback')));
      final payload = responseLog.data as Map<String, dynamic>;
      final result = payload['result'] as Map<String, dynamic>;
      expect(result['item_count'], 1);
      expect(result['total_item_rows'], 1);
      final items = result['items'] as List<dynamic>;
      expect((items.single as Map)['rows'], 'omitted_from_socket_log');
      expect((items.single as Map)['column_metadata_count'], 1);
    });

    test('should stop rpc:response ACK retries after socket generation changes', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);

      final ackAttemptStarted = Completer<void>();
      final releaseAckAttempt = Completer<void>();
      var ackAttempts = 0;
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        if (ackAttempts == 1) {
          ackAttemptStarted.complete();
          await releaseAckAttempt.future;
          throw Exception('ack timeout');
        }
        throw StateError('stale socket retry should not happen');
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      final result = await client.sendResponse(
        QueryResponse(
          id: 'exec-ack',
          requestId: 'req-ack',
          agentId: 'agent-1',
          data: const [],
          timestamp: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      expect(result.isSuccess(), isTrue);
      await ackAttemptStarted.future.timeout(const Duration(seconds: 1));

      await client.disconnect();
      releaseAckAttempt.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 1);
      expect(emitted.where((item) => item.event == 'rpc:response'), isEmpty);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckAbortedConnectionChangeCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 0);
    });

    test('should record rpc:response ACK success outcome', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      final ackDelivered = Completer<void>();
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        if (!ackDelivered.isCompleted) {
          ackDelivered.complete();
        }
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      final result = await client.sendResponse(
        QueryResponse(
          id: 'exec-ack-success',
          requestId: 'req-ack-success',
          agentId: 'agent-1',
          data: const [],
          timestamp: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      expect(result.isSuccess(), isTrue);
      await ackDelivered.future.timeout(const Duration(seconds: 1));
      await Future<void>.delayed(Duration.zero);

      expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckAbortedConnectionChangeCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(emitted.where((item) => item.event == 'rpc:response'), isEmpty);
    });

    test('should record rpc:response ACK fallback outcome when retries exhaust', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenThrow(Exception('ack timeout'));

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      final result = await client.sendResponse(
        QueryResponse(
          id: 'exec-ack-fallback',
          requestId: 'req-ack-fallback',
          agentId: 'agent-1',
          data: const [],
          timestamp: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      expect(result.isSuccess(), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, greaterThan(0));
      expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckAbortedConnectionChangeCount, 0);
      expect(emitted.where((item) => item.event == 'rpc:response'), hasLength(1));
    });

    test('should emit sql.execute rpc response without Socket.IO ACK when delivery guarantees are enabled', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('sql.execute response should not wait for Socket.IO ACK');
      });
      when(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(
          id: request.id,
          result: <String, dynamic>{
            'rows': const [
              {'CodCliente': 1},
            ],
            'row_count': 1,
          },
        );
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'req-codcliente-001',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente'},
        }),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 0);
      final responses = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responses, hasLength(1));
      final responsePayload = decodeWirePayload(responses.single.data) as Map<String, dynamic>;
      expect(responsePayload['id'], 'req-codcliente-001');
      final result = responsePayload['result'] as Map<String, dynamic>;
      expect(result['row_count'], 1);
      expect(result['rows'], [
        {'CodCliente': 1},
      ]);
    });

    test('should emit SQL concurrency-limit error without Socket.IO ACK', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('sql.execute concurrency error should not wait for Socket.IO ACK');
      });
      final unblockDispatch = Completer<RpcResponse>();
      when(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((_) => unblockDispatch.future);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      for (var i = 0; i <= ConnectionConstants.maxConcurrentRpcHandlers; i++) {
        emitEvent(
          'rpc:request',
          encodeWirePayload(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'sql-concurrent-$i',
            'method': 'sql.execute',
            'params': {'sql': 'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente'},
          }),
        );
      }

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
      final rateLimitedResponses = emitted
          .where((item) => item.event == 'rpc:response')
          .map((item) => decodeWirePayload(item.data) as Map<String, dynamic>)
          .where((payload) => (payload['error'] as Map?)?['code'] == RpcErrorCode.rateLimited)
          .toList();
      expect(rateLimitedResponses, hasLength(1));
      expect(rateLimitedResponses.single['id'], 'sql-concurrent-${ConnectionConstants.maxConcurrentRpcHandlers}');
      expect(
        ((rateLimitedResponses.single['error'] as Map<String, dynamic>)['data'] as Map<String, dynamic>)['reason'],
        RpcInboundConstants.concurrentHandlersExceededReason,
      );

      unblockDispatch.complete(
        RpcResponse.success(
          id: 'sql-concurrent-complete',
          result: const <String, dynamic>{
            'execution_id': 'exec-sql-concurrent-complete',
            'started_at': '2026-05-31T22:45:02.900Z',
            'finished_at': '2026-05-31T22:45:02.965Z',
            'row_count': 0,
            'rows': <Map<String, dynamic>>[],
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
    });

    test('should emit invalid sql.execute params response without Socket.IO ACK', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('invalid sql.execute response should not wait for Socket.IO ACK');
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'insomnia-bridge-002',
          'method': 'sql.execute',
          'params': {
            'sql': 'SELECT CodCliente, Nome FROM Cliente ORDER BY CodCliente',
            'options': {'page_size': 10},
          },
        }),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 0);
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
      final responses = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responses, hasLength(1));
      final responsePayload = decodeWirePayload(responses.single.data) as Map<String, dynamic>;
      expect(responsePayload['id'], 'insomnia-bridge-002');
      final error = responsePayload['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.invalidParams);
      expect((error['data'] as Map<String, dynamic>)['reason'], RpcErrorCode.getReason(RpcErrorCode.invalidParams));
    });

    test('should dispatch Insomnia-style paginated sql.execute with real JSON Schema validator without ACK', () async {
      final schemaValidator = await buildJsonSchemaValidator();
      client = SocketIOTransportClientV2(
        dataSource: mockDataSource,
        negotiator: mockNegotiator,
        rpcDispatcher: mockDispatcher,
        featureFlags: mockFeatureFlags,
        options: SocketIOTransportClientV2Options(
          protocolMetricsCollector: metricsCollector,
          metricsCollector: rpcMetricsCollector,
          jsonSchemaValidator: schemaValidator,
        ),
      );
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('valid sql.execute response should not wait for Socket.IO ACK');
      });
      when(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(
          id: request.id,
          result: <String, dynamic>{
            'execution_id': 'exec-insomnia-bridge-002',
            'started_at': '2026-05-31T22:45:02.900Z',
            'finished_at': '2026-05-31T22:45:02.965Z',
            'rows': const [
              {'CodCliente': 1, 'Nome': 'CONSUMIDOR'},
            ],
            'row_count': 1,
          },
        );
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'insomnia-bridge-002',
          'method': 'sql.execute',
          'api_version': '2.10',
          'meta': {'trace_id': '00000000-0000-4000-8000-000000000002'},
          'params': {
            'sql': 'SELECT CodCliente, Nome FROM Cliente ORDER BY CodCliente',
            'client_token': 'token',
            'options': {'page': 1, 'page_size': 10},
          },
        }),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      verify(
        () => mockDispatcher.dispatch(
          any(
            that: isA<RpcRequest>()
                .having((request) => request.id, 'id', 'insomnia-bridge-002')
                .having((request) => request.method, 'method', 'sql.execute'),
          ),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);

      final responses = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responses, hasLength(1));
      final responsePayload = decodeWirePayload(responses.single.data) as Map<String, dynamic>;
      expect(responsePayload['id'], 'insomnia-bridge-002');
      expect(responsePayload['error'], isNull);
      expect((responsePayload['result'] as Map<String, dynamic>)['row_count'], 1);
    });

    test('should reject preserve pagination with real JSON Schema validator without ACK', () async {
      final schemaValidator = await buildJsonSchemaValidator();
      client = SocketIOTransportClientV2(
        dataSource: mockDataSource,
        negotiator: mockNegotiator,
        rpcDispatcher: mockDispatcher,
        featureFlags: mockFeatureFlags,
        options: SocketIOTransportClientV2Options(
          protocolMetricsCollector: metricsCollector,
          metricsCollector: rpcMetricsCollector,
          jsonSchemaValidator: schemaValidator,
        ),
      );
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('invalid sql.execute response should not wait for Socket.IO ACK');
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'preserve-pagination',
          'method': 'sql.execute',
          'params': {
            'sql': 'SELECT CodCliente, Nome FROM Cliente ORDER BY CodCliente',
            'options': {'page': 1, 'page_size': 10, 'execution_mode': 'preserve'},
          },
        }),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
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
      final responses = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responses, hasLength(1));
      final responsePayload = decodeWirePayload(responses.single.data) as Map<String, dynamic>;
      expect(responsePayload['id'], 'preserve-pagination');
      final error = responsePayload['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.invalidParams);
      expect((error['data'] as Map<String, dynamic>)['reason'], RpcErrorCode.getReason(RpcErrorCode.invalidParams));
    });

    test(
      'should emit sql.executeBatch rpc response without Socket.IO ACK when delivery guarantees are enabled',
      () async {
        when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
        var ackAttempts = 0;
        when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
        when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
          ackAttempts++;
          throw StateError('sql.executeBatch response should not wait for Socket.IO ACK');
        });
        when(
          () => mockDispatcher.dispatch(
            any(),
            any(),
            clientToken: any(named: 'clientToken'),
            streamEmitter: any(named: 'streamEmitter'),
            limits: any(named: 'limits'),
            negotiatedExtensions: any(named: 'negotiatedExtensions'),
          ),
        ).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as RpcRequest;
          return RpcResponse.success(
            id: request.id,
            result: <String, dynamic>{
              'execution_id': 'exec-batch-1',
              'items': const [
                {
                  'index': 0,
                  'ok': true,
                  'rows': [
                    {'CodCliente': 1},
                  ],
                  'row_count': 1,
                },
                {
                  'index': 1,
                  'ok': true,
                  'rows': [
                    {'Nome': 'CONSUMIDOR'},
                  ],
                  'row_count': 1,
                },
              ],
              'total_commands': 2,
              'successful_commands': 2,
              'failed_commands': 0,
            },
          );
        });

        final connectFuture = client.connect('https://hub.test', 'agent-1');
        emitEvent('connect');
        await connectFuture;
        await negotiateProtocol();
        emitted.clear();

        emitEvent(
          'rpc:request',
          encodeWirePayload(<String, dynamic>{
            'jsonrpc': '2.0',
            'id': 'insomnia-manual-batch-001',
            'method': 'sql.executeBatch',
            'params': {
              'commands': const [
                {'sql': 'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente'},
                {'sql': 'SELECT TOP 1 Nome FROM Cliente ORDER BY CodCliente'},
              ],
              'client_token': 'token',
            },
          }),
        );

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(ackAttempts, 0);
        expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteBatchCount, 1);
        expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 0);
        expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
        expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
        expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 0);
        final responses = emitted.where((item) => item.event == 'rpc:response').toList();
        expect(responses, hasLength(1));
        final responsePayload = decodeWirePayload(responses.single.data) as Map<String, dynamic>;
        expect(responsePayload['id'], 'insomnia-manual-batch-001');
        final result = responsePayload['result'] as Map<String, dynamic>;
        expect(result['total_commands'], 2);
        expect(result['items'], hasLength(2));
      },
    );

    test('should return replay error without Socket.IO ACK when sql.execute id is duplicated', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('duplicate sql.execute response should not wait for Socket.IO ACK');
      });
      when(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(
          id: request.id,
          result: <String, dynamic>{
            'rows': const [
              {'CodCliente': 1},
            ],
            'row_count': 1,
          },
        );
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      Map<String, dynamic> requestPayload() {
        return <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'duplicated-sql-id',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente'},
        };
      }

      emitEvent('rpc:request', encodeWirePayload(requestPayload()));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      emitEvent('rpc:request', encodeWirePayload(requestPayload()));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 2);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckDeliveredCount, 0);
      verify(
        () => mockDispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);

      final responses = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responses, hasLength(2));
      final replayPayload = decodeWirePayload(responses.last.data) as Map<String, dynamic>;
      expect(replayPayload['id'], 'duplicated-sql-id');
      final error = replayPayload['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.replayDetected);
      expect((error['data'] as Map<String, dynamic>)['reason'], RpcErrorCode.getReason(RpcErrorCode.replayDetected));
    });

    test('should return strict batch duplicate-id SQL error without Socket.IO ACK', () async {
      when(() => mockFeatureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketBatchStrictValidation).thenReturn(true);
      var ackAttempts = 0;
      when(() => mockSocket.timeout(any<int>())).thenReturn(mockSocket);
      when(() => mockSocket.emitWithAckAsync('rpc:response', any<dynamic>())).thenAnswer((_) async {
        ackAttempts++;
        throw StateError('duplicate batch sql.execute response should not wait for Socket.IO ACK');
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<Map<String, dynamic>>[
          {
            'jsonrpc': '2.0',
            'id': 'duplicated-batch-sql-id',
            'method': 'sql.execute',
            'params': {'sql': 'SELECT TOP 1 CodCliente FROM Cliente ORDER BY CodCliente'},
          },
          {
            'jsonrpc': '2.0',
            'id': 'duplicated-batch-sql-id',
            'method': 'sql.execute',
            'params': {'sql': 'SELECT TOP 1 Nome FROM Cliente ORDER BY CodCliente'},
          },
        ]),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(ackAttempts, 0);
      expect(rpcMetricsCollector.rpcResponseAckSkippedSqlExecuteCount, 1);
      expect(rpcMetricsCollector.rpcResponseAckFallbackWithoutAckCount, 0);
      expect(rpcMetricsCollector.rpcResponseAckRetryCount, 0);
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

      final responses = emitted.where((item) => item.event == 'rpc:response').toList();
      expect(responses, hasLength(1));
      final responsePayload = decodeWirePayload(responses.single.data) as Map<String, dynamic>;
      expect(responsePayload['id'], isNull);
      final error = responsePayload['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.invalidRequest);
      expect((error['data'] as Map<String, dynamic>)['reason'], RpcBatchConstants.duplicateRequestIdsReason);
    });

    test('should register reconnect lifecycle handlers on Socket.IO manager', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');

      verify(() => mockManager.on('reconnect', any())).called(1);
      verify(() => mockManager.on('reconnect_attempt', any())).called(1);
      verify(() => mockManager.on('reconnect_failed', any())).called(1);
      verify(() => mockManager.on('reconnect_error', any())).called(1);
      verifyNever(() => mockSocket.on('reconnect', any()));
      verifyNever(() => mockSocket.on('reconnect_attempt', any()));
      verifyNever(() => mockSocket.on('reconnect_failed', any()));
      verifyNever(() => mockSocket.on('reconnect_error', any()));

      emitEvent('connect');
      await connectFuture;
    });

    test('should remove manager reconnect subscriptions on connect_error', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      expect(managerHandlers.keys, containsAll(<String>['reconnect', 'reconnect_attempt', 'reconnect_failed']));

      emitEvent('connect_error', 'offline');
      final result = await connectFuture;

      expect(result.isError(), isTrue);
      expect(managerHandlers, isEmpty);
      verify(() => mockSocket.disconnect()).called(1);
      verify(() => mockSocket.dispose()).called(1);
    });

    test(
      'should complete connect with transport timeout failure when connect event never arrives',
      () {
        fakeAsync((async) {
          Result<void>? result;
          client.connect('https://hub.test', 'agent-1').then((value) => result = value);
          async.flushMicrotasks();

          async.elapse(
            const Duration(milliseconds: ConnectionConstants.socketConnectionTimeoutMs),
          );
          async.flushMicrotasks();

          expect(result, isNotNull);
          final failure = requireNetworkFailure(result!);
          expect(failure.context['timeout'], isTrue);
          expect(failure.context['timeout_stage'], 'transport');
          expect(failure.context['operation'], 'connect');
          verify(() => mockSocket.disconnect()).called(1);
          verify(() => mockSocket.dispose()).called(1);
        });
      },
    );

    test('should re-register after manager reconnect and notify after capabilities', () async {
      final notifications = <HubLifecycleNotification>[];
      client.setOnHubLifecycle(notifications.add);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitManagerEvent('reconnect', 2);
      await Future<void>.delayed(Duration.zero);

      expect(emitted.any((item) => item.event == 'agent:register'), isTrue);
      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );
      await Future<void>.delayed(Duration.zero);

      expect(notifications.whereType<HubTransportAutoReconnectSucceeded>(), hasLength(1));
    });

    test('should request application recovery when post-reconnect register throws', () async {
      var profileCalls = 0;
      client = SocketIOTransportClientV2(
        dataSource: mockDataSource,
        negotiator: mockNegotiator,
        rpcDispatcher: mockDispatcher,
        featureFlags: mockFeatureFlags,
        options: SocketIOTransportClientV2Options(
          registerProfileProvider: () async {
            profileCalls += 1;
            if (profileCalls > 1) {
              throw StateError('profile unavailable');
            }
            return null;
          },
          protocolMetricsCollector: metricsCollector,
          metricsCollector: rpcMetricsCollector,
        ),
      );
      var reconnectRequests = 0;
      client.setOnReconnectionNeeded(() => reconnectRequests++);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();

      emitManagerEvent('reconnect', 2);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(profileCalls, 2);
      expect(reconnectRequests, 1);
    });

    test('should escalate to application recovery when manager reconnect fails', () async {
      var reconnectRequests = 0;
      client.setOnReconnectionNeeded(() => reconnectRequests++);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      emitManagerEvent('reconnect_failed');

      expect(reconnectRequests, 1);
    });

    test('should request token refresh only for auth-related manager reconnect errors', () async {
      var tokenRefreshRequests = 0;
      client.setOnTokenExpired(() => tokenRefreshRequests++);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      emitManagerEvent('reconnect_error', 'connection refused');
      expect(tokenRefreshRequests, 0);

      emitManagerEvent('reconnect_error', <String, dynamic>{
        'code': 'auth_failed',
        'message': 'Hub rejected the token',
      });
      expect(tokenRefreshRequests, 1);
    });

    test('should emit agent:ready after capabilities when readiness ack is negotiated', () async {
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
            'notificationNullIdCompatibility': true,
            'protocolReadyAck': true,
            'signatureRequired': false,
            'signatureAlgorithms': ['hmac-sha256'],
          },
        ),
      );

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      emitted.clear();

      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': const ProtocolCapabilities(
            protocols: ['jsonrpc-v2'],
            encodings: ['json'],
            compressions: ['gzip', 'none'],
            extensions: {
              'binaryPayload': true,
              'transportFrame': 'payload-frame/1.0',
              'notificationNullIdCompatibility': true,
              'protocolReadyAck': true,
              'signatureRequired': false,
              'signatureAlgorithms': ['hmac-sha256'],
            },
          ).toJson(),
        }),
      );

      await Future<void>.delayed(Duration.zero);

      final readyPayload =
          decodeWirePayload(
                emitted.firstWhere((item) => item.event == 'agent:ready').data,
              )
              as Map<String, dynamic>;
      expect(readyPayload['agent_id'], 'agent-1');
      expect(readyPayload['protocol'], 'jsonrpc-v2');
      expect(readyPayload['timestamp'], isA<String>());
    });

    test('should notify lifecycle when initial protocol negotiation is ready', () async {
      final notifications = <HubLifecycleNotification>[];
      client.setOnHubLifecycle(notifications.add);

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );

      await Future<void>.delayed(Duration.zero);

      expect(notifications.whereType<HubProtocolReady>(), hasLength(1));
      expect(notifications.whereType<HubTransportAutoReconnectSucceeded>(), isEmpty);
    });

    test('should keep hub lifecycle callback after disconnect for recovery reconnect', () async {
      final notifications = <HubLifecycleNotification>[];
      client.setOnHubLifecycle(notifications.add);

      final firstConnect = client.connect('https://hub.test', 'agent-1', authToken: 'token-1');
      emitEvent('connect');
      await firstConnect;
      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(notifications.whereType<HubProtocolReady>(), hasLength(1));

      await client.disconnect();

      final secondConnect = client.connect('https://hub.test', 'agent-1', authToken: 'token-2');
      emitEvent('connect');
      await secondConnect;
      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );

      await Future<void>.delayed(Duration.zero);

      expect(notifications.whereType<HubProtocolReady>(), hasLength(2));
    });

    test('should keep token-expired callback after disconnect', () async {
      var tokenExpiredCalls = 0;
      client.setOnTokenExpired(() => tokenExpiredCalls++);

      final first = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await first;
      await client.disconnect();

      final second = client.connect('https://hub.test', 'agent-1', authToken: 'bad');
      emitEvent('connect');
      emitEvent('connect_error', <dynamic, dynamic>{
        'code': 'auth_failed',
        'message': 'Hub rejected the token',
      });
      final result = await second;

      expect(result.isError(), isTrue);
      expect(tokenExpiredCalls, 1);
    });

    test('should keep reconnection-needed callback after disconnect', () async {
      var reconnectCalls = 0;
      client.setOnReconnectionNeeded(() => reconnectCalls++);

      final first = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await first;
      await negotiateProtocol();
      await client.disconnect();

      final second = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await second;
      await negotiateProtocol();
      emitManagerEvent('reconnect_failed');
      await Future<void>.delayed(Duration.zero);

      expect(reconnectCalls, 1);
    });

    test('should fail fast when binary PayloadFrame transport is disabled', () async {
      when(() => mockFeatureFlags.enableBinaryPayload).thenReturn(false);

      final result = await client.connect('https://hub.test', 'agent-1');

      expect(result.isError(), isTrue);
      verifyNever(
        () => mockDataSource.createSocket(
          any(),
          authToken: any(named: 'authToken'),
        ),
      );
    });

    test('should request token refresh for dynamic-map auth connect errors', () async {
      var tokenRefreshRequested = false;
      client.setOnTokenExpired(() {
        tokenRefreshRequested = true;
      });

      final connectFuture = client.connect(
        'https://hub.test',
        'agent-1',
        authToken: 'expired-token',
      );
      emitEvent('connect_error', <dynamic, dynamic>{
        'code': 'auth_failed',
        'message': 'Hub rejected the token',
      });

      final result = await connectFuture;

      expect(result.isError(), isTrue);
      expect(tokenRefreshRequested, isTrue);
      verify(
        () => mockDataSource.createSocket(
          'https://hub.test',
          authToken: 'expired-token',
        ),
      ).called(1);
    });

    test('should include hub_code and hub_reason in connect failure context', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect_error', <String, dynamic>{
        'code': 'hub_unavailable',
        'reason': 'maintenance_window',
        'message': 'Hub is temporarily unavailable',
      });

      final result = await connectFuture;

      final failure = requireNetworkFailure(result);
      expect(failure.context['hub_code'], 'hub_unavailable');
      expect(failure.context['hub_reason'], 'maintenance_window');
      expect(failure.context['operation'], 'connect');
    });

    test('should fail connect when local agent:register validation fails', () async {
      when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(true);
      var reconnectionRequested = false;
      client.setOnReconnectionNeeded(() {
        reconnectionRequested = true;
      });

      final connectFuture = client.connect('https://hub.test', '');
      emitEvent('connect');
      final result = await connectFuture;

      expect(result.isError(), isTrue);
      expect(reconnectionRequested, isTrue);
      expect(emitted.any((item) => item.event == 'agent:register'), isFalse);
      verify(() => mockSocket.disconnect()).called(1);
      verify(() => mockSocket.dispose()).called(1);
    });

    test('should close current socket when register error is a known terminal code', () async {
      var reconnectionRequested = false;
      client.setOnReconnectionNeeded(() {
        reconnectionRequested = true;
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      // 'auth_failed' is a known-terminal code — should force reconnect.
      emitEvent('agent:register_error', {
        'code': 'auth_failed',
        'message': 'authentication failed',
      });

      expect(reconnectionRequested, isTrue);
      verify(() => mockSocket.disconnect()).called(1);
      verify(() => mockSocket.dispose()).called(1);
    });

    test('should keep socket open when dynamic register error is recoverable', () async {
      var reconnectionRequested = false;
      client.setOnReconnectionNeeded(() {
        reconnectionRequested = true;
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      emitEvent('agent:register_error', <dynamic, dynamic>{
        'code': 'transient_failure',
        'message': 'try again',
      });

      expect(reconnectionRequested, isFalse);
      verifyNever(() => mockSocket.disconnect());
      verifyNever(() => mockSocket.dispose());
    });

    test('should record protocol metrics for framed send and receive paths', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;

      emitEvent(
        'agent:capabilities',
        encodeWirePayload({
          'capabilities': ProtocolCapabilities.defaultCapabilities().toJson(),
        }),
      );

      await Future<void>.delayed(Duration.zero);

      expect(metricsCollector.metrics, isNotEmpty);
      expect(
        metricsCollector.metrics.any((metric) => metric.direction == 'send'),
        isTrue,
      );
      expect(
        metricsCollector.metrics.any((metric) => metric.direction == 'receive'),
        isTrue,
      );
      expect(
        metricsCollector.metrics.any((metric) => metric.eventName == 'agent:register'),
        isTrue,
      );
      expect(
        metricsCollector.metrics.any((metric) => metric.eventName == 'agent:capabilities'),
        isTrue,
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
        await negotiateProtocol();
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
                  emitted.firstWhere((item) => item.event == 'rpc:response').data,
                )
                as Map<String, dynamic>;
        final error = responsePayload['error'] as Map<String, dynamic>;
        expect(error['code'], RpcErrorCode.invalidRequest);
      },
    );

    test('should respond to rpc.discover with OpenRPC document', () async {
      when(
        () => mockDispatcher.dispatch(
          any(that: predicate<RpcRequest>((request) => request.method == 'rpc.discover')),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(
          id: request.id,
          result: <String, dynamic>{
            'openrpc': '1.3.2',
            'info': <String, dynamic>{'title': 'Plug Agente', 'version': '1'},
            'methods': <dynamic>[],
          },
        );
      });

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
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

      verify(
        () => mockDispatcher.dispatch(
          any(that: predicate<RpcRequest>((request) => request.method == 'rpc.discover')),
          'agent-1',
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);
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
        expect(managerHandlers, isEmpty);
        expect(reconnectionRequested, isTrue);
      },
    );

    test(
      'should disconnect when hub requires transport signature and signer is missing',
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
        expect(managerHandlers, isEmpty);
        expect(reconnectionRequested, isTrue);
      },
    );

    test('should reject rpc request that is not a PayloadFrame', () async {
      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
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

    test('should emit fallback internal errors as PayloadFrame', () async {
      when(() => mockFeatureFlags.enableSocketSchemaValidation).thenReturn(true);
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
        (_) async => RpcResponse.success(id: 'req-invalid-response', result: 'invalid-result'),
      );

      final connectFuture = client.connect('https://hub.test', 'agent-1');
      emitEvent('connect');
      await connectFuture;
      await negotiateProtocol();
      emitted.clear();

      emitEvent(
        'rpc:request',
        encodeWirePayload(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'sql.execute',
          'id': 'req-invalid-response',
          'params': {'sql': 'SELECT 1'},
        }),
      );

      await Future<void>.delayed(Duration.zero);

      final response = emitted.firstWhere((item) => item.event == 'rpc:response');
      expect(response.data, isA<Map<String, dynamic>>());
      expect((response.data as Map<String, dynamic>)['schemaVersion'], '1.0');
      final responsePayload = decodeWirePayload(response.data) as Map<String, dynamic>;
      final error = responsePayload['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.internalError);
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
          await negotiateProtocol();
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
                    emitted.firstWhere((item) => item.event == 'rpc:response').data,
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
          await negotiateProtocol();
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
                    emitted.firstWhere((item) => item.event == 'rpc:response').data,
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
          final mockGetClientTokenPolicy = MockGetClientTokenPolicy();
          when(() => mockGetClientTokenPolicy.call(any())).thenAnswer(
            (_) async => const Success(
              ClientTokenPolicy(
                clientId: 'test-client',
                allTables: false,
                allViews: false,
                allPermissions: false,
                rules: [],
              ),
            ),
          );

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
            () => mockGateway.executeQuery(
              any(),
              timeout: any(named: 'timeout'),
              database: any(named: 'database'),
            ),
          ).thenAnswer((_) async => Success(queryResponse));
          when(
            () => mockNormalizer.normalize(any()),
          ).thenAnswer((_) => queryResponse);
          when(
            () => mockNormalizer.normalizeAsync(any()),
          ).thenAnswer((_) async => queryResponse);

          final realDispatcher = RpcMethodDispatcher(
            databaseGateway: mockGateway,
            healthService: HealthService(
              metricsCollector: MetricsCollector(),
              gateway: mockGateway,
            ),
            normalizerService: mockNormalizer,
            uuid: const Uuid(),
            authorizeSqlOperation: mockAuthorize,
            getClientTokenPolicy: mockGetClientTokenPolicy,
            getPolicyRateLimiter: _transportTestNoopGetPolicyRateLimiter,
            featureFlags: mockFeatureFlags,
            streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
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
          await negotiateProtocol();
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

          final responseItems = emitted.where((item) => item.event == 'rpc:response').toList();
          expect(responseItems, isNotEmpty);
          final responsePayload = decodeWirePayload(responseItems.first.data) as Map<String, dynamic>;
          final result = responsePayload['result'] as Map<String, dynamic>?;
          expect(result, isNotNull);
          expect(result!['sql_handling_mode'], 'preserve');
          expect(result['effective_max_rows'], isNotNull);
        },
      );
    });
  });
}
