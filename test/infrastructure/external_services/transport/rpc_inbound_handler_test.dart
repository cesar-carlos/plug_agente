import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/constants/agent_action_policy_defaults.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_inbound_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';
import 'package:result_dart/result_dart.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

/// Fake validator that always rejects every call — used to test schema-gate paths.
class _AlwaysRejectingValidator extends JsonSchemaContractValidator {
  _AlwaysRejectingValidator() : super(loader: TransportSchemaLoader(assetLoader: (_) async => '{}'));

  @override
  Result<void> validate({
    required String schemaId,
    required Object? payload,
    String direction = 'unknown',
  }) => Failure(
    domain.ValidationFailure.withContext(
      message: 'schema_rejected_in_test',
      context: {'schema_id': schemaId},
    ),
  );

  @override
  bool isLoaded(String schemaId) => true;
}

class _MockDispatcher extends Mock implements IRpcRequestDispatcher, RpcMethodDispatcher {}

class _MockStreamEmitter extends Mock implements IRpcStreamEmitter {}

Map<String, dynamic> _minimalRpcBatchItemForDisallowedAgentAction(String method, String id) {
  return switch (method) {
    AgentActionRpcConstants.agentActionRunRpcMethodName => {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': {
        'action_id': 'action-1',
        'idempotency_key': 'idem-$id',
      },
    },
    AgentActionRpcConstants.agentActionCancelRpcMethodName => {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': {
        'execution_id': 'execution-1',
      },
    },
    _ => throw UnsupportedError('Add minimal batch RPC item for method "$method"'),
  };
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RpcRequest(jsonrpc: '2.0', method: 'sql.execute', id: 'fallback'),
    );
    registerFallbackValue(const TransportLimits());
    registerFallbackValue(_MockStreamEmitter());
  });

  late _MockFeatureFlags featureFlags;
  late _MockDispatcher dispatcher;
  late ProtocolConfig protocol;
  late List<dynamic> emittedResponses;
  late List<Map<Object?, String>> emittedResponseMethodContexts;
  late List<({String event, dynamic payload})> emittedEvents;
  late List<bool> hubSqlCaptureTransitions;
  late RpcInboundHandler handler;
  late MetricsCollector inboundMetrics;

  setUp(() {
    inboundMetrics = MetricsCollector();
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
    when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(false);
    when(() => featureFlags.enableSocketStreamingChunks).thenReturn(false);
    when(() => featureFlags.enableSocketNotificationsContract).thenReturn(true);
    when(() => featureFlags.enableSocketBatchStrictValidation).thenReturn(false);
    when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(false);
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    when(() => featureFlags.enableClientTokenPolicyIntrospection).thenReturn(false);
    when(() => featureFlags.enablePayloadSigning).thenReturn(false);
    when(() => featureFlags.requireIncomingPayloadSignatures).thenReturn(false);
    when(() => featureFlags.outboundCompressionMode).thenReturn(OutboundCompressionMode.none);
    when(() => featureFlags.compressionThreshold).thenReturn(2048);
    when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(false);

    dispatcher = _MockDispatcher();
    protocol = const ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'none',
    );
    emittedResponses = [];
    emittedResponseMethodContexts = <Map<Object?, String>>[];
    emittedEvents = [];
    hubSqlCaptureTransitions = <bool>[];

    final pipelineCache = TransportPipelineCache(
      protocolProvider: () => protocol,
      hasReceivedCapabilities: () => true,
      featureFlags: featureFlags,
    );
    final summarizer = PayloadLogSummarizer(thresholdBytes: 8192);
    final frameCodec = PayloadFrameCodec(
      pipelineCache: pipelineCache,
      protocolProvider: () => protocol,
      localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
      hasReceivedCapabilities: () => true,
      localShouldSignOutgoing: () => false,
      localRequiresIncomingSignature: () => false,
    );
    final preparer = RpcResponsePreparer(
      featureFlags: featureFlags,
      logSummarizer: summarizer,
      contractValidator: const RpcContractValidator(),
      protocolProvider: () => protocol,
      usesBinaryTransport: () => true,
      agentIdProvider: () => 'agent-1',
    );
    final authzLogger = AuthorizationDecisionLogger(
      featureFlags: featureFlags,
      logMessage: (_, _, _) {},
      agentIdProvider: () => 'agent-1',
      onTokenRefreshRequested: () {},
    );

    handler = RpcInboundHandler(
      featureFlags: featureFlags,
      protocolProvider: () => protocol,
      agentIdProvider: () => 'agent-1',
      frameCodec: frameCodec,
      logSummarizer: summarizer,
      responsePreparer: preparer,
      authorizationDecisionLogger: authzLogger,
      dispatcher: dispatcher,
      requestGuard: RpcRequestGuard(),
      schemaValidator: const RpcRequestSchemaValidator(),
      streamEmitterFactory: _MockStreamEmitter.new,
      emitRpcResponse: (response) async {
        emittedResponses.add(response);
      },
      emitRpcResponseWithMethodContext: (response, {methodsById = const <Object?, String>{}}) async {
        emittedResponses.add(response);
        emittedResponseMethodContexts.add(Map<Object?, String>.from(methodsById));
      },
      emitEvent: (event, payload) async {
        emittedEvents.add((event: event, payload: payload));
      },
      hasReceivedCapabilities: () => true,
      metricsCollector: inboundMetrics,
      setHubSqlDashboardCapturePaused: (paused) => hubSqlCaptureTransitions.add(paused),
    );
  });

  group('concurrency slots', () {
    test('tryAcquireSlot returns true up to the cap', () {
      final acquired = <bool>[];
      for (var i = 0; i < 32; i++) {
        acquired.add(handler.tryAcquireSlot());
      }
      expect(acquired.every((b) => b), isTrue);
    });

    test('tryAcquireSlot returns false past the cap', () {
      for (var i = 0; i < 32; i++) {
        handler.tryAcquireSlot();
      }
      expect(handler.tryAcquireSlot(), isFalse);
    });

    test('releaseSlot frees a slot for reuse', () {
      for (var i = 0; i < 32; i++) {
        handler.tryAcquireSlot();
      }
      handler.releaseSlot();
      expect(handler.tryAcquireSlot(), isTrue);
    });

    test('emitConcurrencyLimitedError emits a rateLimited response', () async {
      await handler.emitConcurrencyLimitedError({'jsonrpc': '2.0', 'id': 'req-x'});

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error?.code, RpcErrorCode.rateLimited);
      expect(response.id, 'req-x');
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['reason'], RpcInboundConstants.concurrentHandlersExceededReason);
      expect(
        data['technical_message'],
        RpcInboundConstants.concurrentHandlersExceededTechnicalMessage(ConnectionConstants.maxConcurrentRpcHandlers),
      );
    });

    test('emitConcurrencyLimitedError preserves SQL method context for ACK bypass', () async {
      await handler.emitConcurrencyLimitedError({
        'jsonrpc': '2.0',
        'id': 'req-sql-rate-limit',
        'method': 'sql.execute',
      });

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error?.code, RpcErrorCode.rateLimited);
      expect(response.id, 'req-sql-rate-limit');
      expect(emittedResponseMethodContexts.single, <Object?, String>{
        'req-sql-rate-limit': 'sql.execute',
      });
    });

    test('handleRequestWithRelease frees slot before slow emit completes', () async {
      final dispatchCompleted = Completer<void>();
      final emitEntered = Completer<void>();
      final unblockEmit = Completer<void>();

      reset(dispatcher);
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((_) async {
        if (!dispatchCompleted.isCompleted) {
          dispatchCompleted.complete();
        }
        return RpcResponse.success(id: 'slot-1', result: <String, dynamic>{'ok': true});
      });

      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'id': 'slot-1',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT 1'},
        },
      )).getOrThrow();

      final throughputHandler = RpcInboundHandler(
        featureFlags: featureFlags,
        protocolProvider: () => protocol,
        agentIdProvider: () => 'agent-1',
        frameCodec: frameCodec,
        logSummarizer: PayloadLogSummarizer(thresholdBytes: 8192),
        responsePreparer: RpcResponsePreparer(
          featureFlags: featureFlags,
          logSummarizer: PayloadLogSummarizer(thresholdBytes: 8192),
          contractValidator: const RpcContractValidator(),
          protocolProvider: () => protocol,
          usesBinaryTransport: () => true,
          agentIdProvider: () => 'agent-1',
        ),
        authorizationDecisionLogger: AuthorizationDecisionLogger(
          featureFlags: featureFlags,
          logMessage: (_, _, _) {},
          agentIdProvider: () => 'agent-1',
          onTokenRefreshRequested: () {},
        ),
        dispatcher: dispatcher,
        requestGuard: RpcRequestGuard(),
        schemaValidator: const RpcRequestSchemaValidator(),
        streamEmitterFactory: _MockStreamEmitter.new,
        emitRpcResponse: (response) async {
          if (!emitEntered.isCompleted) {
            emitEntered.complete();
          }
          await unblockEmit.future;
          emittedResponses.add(response);
        },
        emitEvent: (event, payload) async {
          emittedEvents.add((event: event, payload: payload));
        },
        hasReceivedCapabilities: () => true,
      );

      expect(throughputHandler.tryAcquireSlot(), isTrue);
      final handleFuture = throughputHandler.handleRequestWithRelease(wire);

      await dispatchCompleted.future;
      await emitEntered.future;

      expect(throughputHandler.tryAcquireSlot(), isTrue);

      unblockEmit.complete();
      await handleFuture;
      await Future<void>.delayed(Duration.zero);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error, isNull);
    });

    test('handleRequestWithRelease releases slot on notification-only path without emit', () async {
      reset(dispatcher);
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer(
        (_) async => RpcResponse.success(id: null, result: <String, dynamic>{'handled': true}),
      );

      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'params': <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-notify',
          },
        },
      )).getOrThrow();

      expect(handler.tryAcquireSlot(), isTrue);
      await handler.handleRequestWithRelease(wire);

      expect(emittedResponses, isEmpty);
      expect(handler.tryAcquireSlot(), isTrue);
    });

    test('emitConcurrencyLimitedError unwraps framed payload and calls socket ack once', () async {
      var ackCount = 0;
      final requestBytes = Uint8List.fromList(
        utf8.encode('{"jsonrpc":"2.0","id":"req-frame","method":"sql.execute"}'),
      );
      final frame = PayloadFrame(
        schemaVersion: '1.0',
        enc: 'json',
        cmp: 'none',
        contentType: 'application/json',
        originalSize: requestBytes.length,
        compressedSize: requestBytes.length,
        payload: requestBytes,
        requestId: 'req-frame',
      ).toJson();

      await handler.emitConcurrencyLimitedError([
        frame,
        () {
          ackCount++;
        },
      ]);

      expect(ackCount, 1);
      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.id, 'req-frame');
      expect(response.error?.code, RpcErrorCode.rateLimited);
    });

    test('emitConcurrencyLimitedError calls socket ack once when framed payload cannot expose id', () async {
      var ackCount = 0;
      final requestBytes = Uint8List.fromList(utf8.encode('null'));
      final frame = PayloadFrame(
        schemaVersion: '1.0',
        enc: 'json',
        cmp: 'none',
        contentType: 'application/json',
        originalSize: requestBytes.length,
        compressedSize: requestBytes.length,
        payload: requestBytes,
      ).toJson();

      await handler.emitConcurrencyLimitedError([
        frame,
        () {
          ackCount++;
        },
      ]);

      expect(ackCount, 1);
      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.id, isNull);
      expect(response.error?.code, RpcErrorCode.rateLimited);
    });
  });

  group('transport decode errors', () {
    test('maps invalid JSON payloads to decodingFailed', () async {
      final invalidJsonBytes = Uint8List.fromList(utf8.encode('{not-json'));
      final frame = PayloadFrame(
        schemaVersion: '1.0',
        enc: 'json',
        cmp: 'none',
        contentType: 'application/json',
        originalSize: invalidJsonBytes.length,
        compressedSize: invalidJsonBytes.length,
        payload: invalidJsonBytes,
        requestId: 'bad-json',
      ).toJson();

      await handler.handleRequest(frame);

      final response = emittedResponses.single as RpcResponse;
      expect(response.id, 'bad-json');
      expect(response.error?.code, RpcErrorCode.decodingFailed);
    });

    test('maps invalid gzip payloads to compressionFailed', () async {
      final invalidGzipBytes = Uint8List.fromList(const <int>[1, 2, 3, 4]);
      final frame = PayloadFrame(
        schemaVersion: '1.0',
        enc: 'json',
        cmp: 'gzip',
        contentType: 'application/json',
        originalSize: 128,
        compressedSize: invalidGzipBytes.length,
        payload: invalidGzipBytes,
        requestId: 'bad-gzip',
      ).toJson();

      await handler.handleRequest(frame);

      final response = emittedResponses.single as RpcResponse;
      expect(response.id, 'bad-gzip');
      expect(response.error?.code, RpcErrorCode.compressionFailed);
    });
  });

  group('rpc.discover dispatch', () {
    test('returns the OpenRPC document via the dispatcher', () async {
      when(
        () => dispatcher.dispatch(
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
            'openrpc': '1.3.2',
            'info': <String, dynamic>{'title': 't', 'version': '1'},
            'methods': <dynamic>[],
          },
        );
      });

      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'id': 'disc-1',
          'method': 'rpc.discover',
        },
      )).getOrThrow();

      await handler.handleRequest(wire);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.id, 'disc-1');
      expect(response.result, isA<Map<String, dynamic>>());
      verify(
        () => dispatcher.dispatch(
          any(that: predicate<RpcRequest>((request) => request.method == 'rpc.discover')),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);
    });
  });

  group('agent.action notification contract', () {
    test('should dispatch but not emit rpc response for agent.action notification', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer(
        (_) async => RpcResponse.error(
          id: null,
          error: RpcError(
            code: RpcErrorCode.invalidParams,
            message: RpcErrorCode.getMessage(RpcErrorCode.invalidParams),
            data: RpcErrorCode.buildErrorData(
              code: RpcErrorCode.invalidParams,
              technicalMessage: 'agent.action.run requires a JSON-RPC id',
              reason: AgentActionRpcConstants.remoteAgentActionNotificationNotAllowedRpcReason,
            ),
          ),
        ),
      );

      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'method': AgentActionRpcConstants.agentActionRunRpcMethodName,
          'params': <String, dynamic>{
            'action_id': 'action-1',
            'idempotency_key': 'idem-1',
          },
        },
      )).getOrThrow();

      await handler.handleRequest(wire);

      expect(emittedResponses, isEmpty);
      verify(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);
    });
  });

  group('stream emitter selection', () {
    test('creates emitter for negotiated DB streaming even when materialized chunk flag is disabled', () async {
      when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(true);
      when(() => featureFlags.enableSocketStreamingChunks).thenReturn(false);
      protocol = const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
        negotiatedExtensions: {'streamingResults': true},
      );
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((_) async => RpcResponse.success(id: 'req-stream', result: <String, dynamic>{}));
      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'id': 'req-stream',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT * FROM users'},
        },
      )).getOrThrow();

      await handler.handleRequest(wire);

      final captured = verify(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: captureAny(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).captured;
      expect(captured.single, isA<IRpcStreamEmitter>());
    });
  });

  group('single SQL dashboard capture pause', () {
    test('pauses and resumes dashboard capture for sql.executeBatch', () async {
      when(
        () => dispatcher.dispatch(
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
          result: const <String, dynamic>{
            'items': <dynamic>[],
            'total_commands': 0,
            'successful_commands': 0,
            'failed_commands': 0,
          },
        );
      });

      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'id': 'sql-batch-single',
          'method': 'sql.executeBatch',
          'params': {
            'commands': [
              {'sql': 'SELECT 1'},
            ],
          },
        },
      )).getOrThrow();

      await handler.handleRequest(wire);

      expect(hubSqlCaptureTransitions, [true, false]);
    });
  });

  group('handleBatchRequest', () {
    test('returns invalidRequest for empty batch', () async {
      await handler.handleBatchRequest([]);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error?.code, RpcErrorCode.invalidRequest);
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['detail'], RpcInboundConstants.batchRequestEmptyDetail);
      expect(data['technical_message'], RpcInboundConstants.batchRequestEmptyDetail);
    });

    test('pauses and resumes dashboard capture for batch containing sql.execute', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(id: request.id, result: const <String, dynamic>{'ok': true});
      });

      await handler.handleBatchRequest([
        {
          'jsonrpc': '2.0',
          'id': 'sql-batch-1',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT 1'},
        },
      ]);

      expect(hubSqlCaptureTransitions, [true, false]);
    });

    test('pauses and resumes dashboard capture for batch containing sql.executeBatch', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(id: request.id, result: const <String, dynamic>{'items': <dynamic>[]});
      });

      await handler.handleBatchRequest([
        {
          'jsonrpc': '2.0',
          'id': 'sql-execute-batch-1',
          'method': 'sql.executeBatch',
          'params': {
            'commands': [
              {'sql': 'SELECT 1'},
            ],
          },
        },
      ]);

      expect(hubSqlCaptureTransitions, [true, false]);
    });

    test('does not pause dashboard capture for batch without sql.execute', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((_) async => RpcResponse.success(id: 'health-1', result: const <String, dynamic>{'ok': true}));

      await handler.handleBatchRequest([
        {
          'jsonrpc': '2.0',
          'id': 'health-1',
          'method': 'health.check',
          'params': const <String, dynamic>{},
        },
      ]);

      expect(hubSqlCaptureTransitions, isEmpty);
    });

    test('always resumes dashboard capture when sql.execute batch dispatch throws', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenThrow(Exception('dispatch failed'));

      await handler.handleBatchRequest([
        {
          'jsonrpc': '2.0',
          'id': 'sql-batch-error',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT 1'},
        },
      ]);

      expect(hubSqlCaptureTransitions, [true, false]);
      expect(emittedResponses, isNotEmpty);
      final last = emittedResponses.last;
      final response = switch (last) {
        final List<RpcResponse> responses when responses.isNotEmpty => responses.first,
        final RpcResponse single => single,
        _ => throw StateError('Unexpected batch response type: ${last.runtimeType}'),
      };
      expect(response.error?.code, RpcErrorCode.internalError);
    });

    test('rejects side-effect agent actions in batch before dispatch', () async {
      const methods = AgentActionRpcConstants.jsonRpcBatchDisallowedAgentActionMethodsOrdered;
      final batch = <Map<String, dynamic>>[
        for (var i = 0; i < methods.length; i++) _minimalRpcBatchItemForDisallowedAgentAction(methods[i], 'id-$i'),
      ];

      await handler.handleBatchRequest(batch);

      expect(emittedResponses, hasLength(1));
      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses, hasLength(methods.length));
      expect(responses.map((response) => response.id), [for (var i = 0; i < methods.length; i++) 'id-$i']);
      expect(
        responses.map((response) => response.error?.code),
        everyElement(RpcErrorCode.invalidRequest),
      );
      expect(
        responses.map((response) {
          final data = response.error?.data as Map<String, dynamic>?;
          return data?['reason'];
        }),
        everyElement(AgentActionRpcConstants.jsonRpcBatchMethodNotAllowedErrorReason),
      );
      verifyNever(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      );
    });

    test('dispatches read-only agent.action.getExecution inside JSON-RPC batch', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer(
        (_) async => RpcResponse.success(
          id: 'get-batch-1',
          result: <String, dynamic>{'execution_id': 'execution-1'},
        ),
      );

      await handler.handleBatchRequest([
        {
          'jsonrpc': '2.0',
          'id': 'get-batch-1',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'params': {
            'execution_id': 'execution-1',
          },
        },
      ]);

      expect(emittedResponses, hasLength(1));
      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses, hasLength(1));
      expect(responses.single.error, isNull);
      expect(responses.single.result, isA<Map<String, dynamic>>());
      expect(
        (responses.single.result! as Map<String, dynamic>)['execution_id'],
        'execution-1',
      );

      verify(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);
    });

    test('dispatches agent.action.validateRun inside JSON-RPC batch', () async {
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer(
        (_) async => RpcResponse.success(
          id: 'validate-batch-1',
          result: <String, dynamic>{
            'valid': true,
            'action_id': 'action-1',
            'action_type': 'commandLine',
          },
        ),
      );

      await handler.handleBatchRequest([
        {
          'jsonrpc': '2.0',
          'id': 'validate-batch-1',
          'method': AgentActionRpcConstants.agentActionValidateRunRpcMethodName,
          'params': {
            'action_id': 'action-1',
            'idempotency_key': 'idem-validate-1',
          },
        },
      ]);

      expect(emittedResponses, hasLength(1));
      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses, hasLength(1));
      expect(responses.single.error, isNull);
      final result = responses.single.result! as Map<String, dynamic>;
      expect(result['valid'], isTrue);
      expect(result['action_id'], 'action-1');

      verify(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);
    });

    test('rejects batch when read-only agent.action RPC count exceeds limit', () async {
      final limit = AgentActionPolicyDefaults.maxAgentActionReadRpcMethodsPerBatch;
      final batch = List<Map<String, dynamic>>.generate(
        limit + 1,
        (index) => {
          'jsonrpc': '2.0',
          'id': 'read-batch-$index',
          'method': AgentActionRpcConstants.agentActionGetExecutionRpcMethodName,
          'params': {'execution_id': 'execution-$index'},
        },
      );

      await handler.handleBatchRequest(batch);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error?.code, RpcErrorCode.invalidRequest);
      final data = response.error!.data as Map<String, dynamic>;
      expect(
        data['reason'],
        AgentActionRpcConstants.jsonRpcBatchAgentActionReadLimitErrorReason,
      );
      expect(data['read_method_count'], limit + 1);
      expect(data['limit'], limit);
      verifyNever(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      );
      expect(
        inboundMetrics.getSnapshot()['rpc_remote_agent_action_batch_read_limit_rejected'],
        1,
      );
    });
  });

  group('protocol_not_ready guard', () {
    test('rejects rpc:request before agent:capabilities is received', () async {
      // Re-create the handler with hasReceivedCapabilities returning false to
      // simulate a hub that sends rpc:request before negotiation completes.
      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => false,
        featureFlags: featureFlags,
      );
      final summarizer = PayloadLogSummarizer(thresholdBytes: 8192);
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => false,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final preparer = RpcResponsePreparer(
        featureFlags: featureFlags,
        logSummarizer: summarizer,
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => protocol,
        usesBinaryTransport: () => true,
        agentIdProvider: () => 'agent-1',
      );
      final authzLogger = AuthorizationDecisionLogger(
        featureFlags: featureFlags,
        logMessage: (_, _, _) {},
        agentIdProvider: () => 'agent-1',
        onTokenRefreshRequested: () {},
      );

      final notReadyHandler = RpcInboundHandler(
        featureFlags: featureFlags,
        protocolProvider: () => protocol,
        agentIdProvider: () => 'agent-1',
        frameCodec: frameCodec,
        logSummarizer: summarizer,
        responsePreparer: preparer,
        authorizationDecisionLogger: authzLogger,
        dispatcher: dispatcher,
        requestGuard: RpcRequestGuard(),
        schemaValidator: const RpcRequestSchemaValidator(),
        streamEmitterFactory: _MockStreamEmitter.new,
        emitRpcResponse: (response) async {
          emittedResponses.add(response);
        },
        emitEvent: (event, payload) async {},
        hasReceivedCapabilities: () => false,
      );

      await notReadyHandler.handleRequest({
        'jsonrpc': '2.0',
        'id': 'req-early',
        'method': 'sql.execute',
        'params': {'sql': 'SELECT 1'},
      });

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error?.code, RpcErrorCode.invalidRequest);
      final data = response.error!.data as Map<String, dynamic>;
      expect(data['reason'], RpcInboundConstants.protocolNotReadyReason);
      // Dispatcher must NOT be invoked when protocol is not ready.
      verifyNever(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      );
    });
  });

  RpcInboundHandler buildHandlerWithValidator(JsonSchemaContractValidator validator) {
    final pipelineCache = TransportPipelineCache(
      protocolProvider: () => protocol,
      hasReceivedCapabilities: () => true,
      featureFlags: featureFlags,
    );
    final summarizer = PayloadLogSummarizer(thresholdBytes: 8192);
    final frameCodec = PayloadFrameCodec(
      pipelineCache: pipelineCache,
      protocolProvider: () => protocol,
      localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
      hasReceivedCapabilities: () => true,
      localShouldSignOutgoing: () => false,
      localRequiresIncomingSignature: () => false,
    );
    final preparer = RpcResponsePreparer(
      featureFlags: featureFlags,
      logSummarizer: summarizer,
      contractValidator: const RpcContractValidator(),
      protocolProvider: () => protocol,
      usesBinaryTransport: () => true,
      agentIdProvider: () => 'agent-1',
    );
    final authzLogger = AuthorizationDecisionLogger(
      featureFlags: featureFlags,
      logMessage: (_, _, _) {},
      agentIdProvider: () => 'agent-1',
      onTokenRefreshRequested: () {},
    );
    return RpcInboundHandler(
      featureFlags: featureFlags,
      protocolProvider: () => protocol,
      agentIdProvider: () => 'agent-1',
      frameCodec: frameCodec,
      logSummarizer: summarizer,
      responsePreparer: preparer,
      authorizationDecisionLogger: authzLogger,
      dispatcher: dispatcher,
      requestGuard: RpcRequestGuard(),
      schemaValidator: const RpcRequestSchemaValidator(),
      streamEmitterFactory: _MockStreamEmitter.new,
      emitRpcResponse: (response) async => emittedResponses.add(response),
      emitEvent: (event, payload) async {},
      hasReceivedCapabilities: () => true,
      jsonSchemaValidator: validator,
    );
  }

  group('batch validation error id (M5)', () {
    test('should use first batch item id in error response when batch fails validation', () async {
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(true);

      final h = buildHandlerWithValidator(_AlwaysRejectingValidator());

      final batch = [
        {
          'jsonrpc': '2.0',
          'id': 'first-id',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT 1'},
        },
        {
          'jsonrpc': '2.0',
          'id': 'second-id',
          'method': 'sql.execute',
          'params': {'sql': 'SELECT 2'},
        },
      ];

      await h.handleBatchRequest(batch);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.id, 'first-id');
    });
  });

  group('schema validation size gate (P1)', () {
    test('skips schema validation for large payloads and dispatches normally', () async {
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(true);
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((_) async => RpcResponse.success(id: 'big-req', result: <String, dynamic>{}));

      final h = buildHandlerWithValidator(_AlwaysRejectingValidator());

      // Build a valid PayloadFrame for the large request so the handler can
      // decode it before checking schema validation.
      final largePayload = {'sql': 'x' * (ConnectionConstants.schemaValidationSkipAboveBytes + 1024)};
      final requestMap = {
        'jsonrpc': '2.0',
        'id': 'big-req',
        'method': 'sql.execute',
        'params': largePayload,
      };
      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      final wire = (await frameCodec.prepareOutgoing(event: 'rpc:request', logicalPayload: requestMap)).getOrThrow();

      await h.handleRequest(wire);

      verify(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(1);
    });
  });

  group('rpc:request_ack coalescing (B2)', () {
    Future<dynamic> frameRequest(String id) async {
      final pipelineCache = TransportPipelineCache(
        protocolProvider: () => protocol,
        hasReceivedCapabilities: () => true,
        featureFlags: featureFlags,
      );
      final frameCodec = PayloadFrameCodec(
        pipelineCache: pipelineCache,
        protocolProvider: () => protocol,
        localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
        hasReceivedCapabilities: () => true,
        localShouldSignOutgoing: () => false,
        localRequiresIncomingSignature: () => false,
      );
      return (await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: <String, dynamic>{
          'jsonrpc': '2.0',
          'id': id,
          'method': 'sql.execute',
          'params': const <String, dynamic>{'sql': 'SELECT 1'},
        },
      )).getOrThrow();
    }

    setUp(() {
      when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(true);
      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          streamEmitter: any(named: 'streamEmitter'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer(
        (invocation) async => RpcResponse.success(
          id: (invocation.positionalArguments[0] as RpcRequest).id,
          result: const <String, dynamic>{'ok': true},
        ),
      );
    });

    test('emits a single rpc:request_ack when only one request is pending after the flush window', () async {
      final wire = await frameRequest('ack-single');

      await handler.handleRequest(wire);
      // Wait long enough for the 5 ms debounce timer to flush.
      await Future<void>.delayed(const Duration(milliseconds: 25));

      final acks = emittedEvents.where((e) => e.event == 'rpc:request_ack').toList();
      expect(acks, hasLength(1));
      final payload = acks.single.payload as Map<String, dynamic>;
      expect(payload['request_id'], 'ack-single');
      expect(emittedEvents.any((e) => e.event == 'rpc:batch_ack'), isFalse);
    });

    test('coalesces a burst into a single rpc:batch_ack with all request ids', () async {
      final wireA = await frameRequest('ack-burst-a');
      final wireB = await frameRequest('ack-burst-b');
      final wireC = await frameRequest('ack-burst-c');

      await Future.wait<void>([
        handler.handleRequest(wireA),
        handler.handleRequest(wireB),
        handler.handleRequest(wireC),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      final batches = emittedEvents.where((e) => e.event == 'rpc:batch_ack').toList();
      expect(batches, hasLength(1));
      final payload = batches.single.payload as Map<String, dynamic>;
      expect(
        (payload['request_ids'] as List).cast<String>(),
        containsAll(<String>['ack-burst-a', 'ack-burst-b', 'ack-burst-c']),
      );
      expect(emittedEvents.any((e) => e.event == 'rpc:request_ack'), isFalse);
    });

    test('does not emit any ack when delivery guarantees are disabled', () async {
      when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(false);
      final wire = await frameRequest('no-ack');

      await handler.handleRequest(wire);
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(emittedEvents.any((e) => e.event == 'rpc:request_ack'), isFalse);
      expect(emittedEvents.any((e) => e.event == 'rpc:batch_ack'), isFalse);
    });

    test('resetAckBuffer drops queued acks without emitting after the timer', () async {
      final wire = await frameRequest('ack-reset');

      await handler.handleRequest(wire);
      handler.resetAckBuffer();
      await Future<void>.delayed(const Duration(milliseconds: 25));

      expect(emittedEvents.any((e) => e.event == 'rpc:request_ack'), isFalse);
      expect(emittedEvents.any((e) => e.event == 'rpc:batch_ack'), isFalse);
    });
  });
}
