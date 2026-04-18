import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_stream_emitter.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/open_rpc_document_loader.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockDispatcher extends Mock implements RpcMethodDispatcher {}

class _MockStreamEmitter extends Mock implements IRpcStreamEmitter {}

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
  late List<({String event, dynamic payload})> emittedEvents;
  late RpcInboundHandler handler;

  setUp(() {
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
    when(() => featureFlags.outboundCompressionMode).thenReturn(OutboundCompressionMode.none);
    when(() => featureFlags.compressionThreshold).thenReturn(2048);

    dispatcher = _MockDispatcher();
    protocol = const ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'none',
    );
    emittedResponses = [];
    emittedEvents = [];

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
      localSignatureRequired: () => false,
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
      openRpcDocumentLoader: OpenRpcDocumentLoader(
        assetLoader: (_) async => '{"openrpc":"1.3.2","info":{"title":"t","version":"1"},"methods":[]}',
        fileLoader: (_) async => throw StateError('unused'),
        cwdProvider: () => '.',
      ),
      dispatcher: dispatcher,
      requestGuard: RpcRequestGuard(),
      schemaValidator: const RpcRequestSchemaValidator(),
      streamEmitterFactory: _MockStreamEmitter.new,
      emitRpcResponse: (response) async {
        emittedResponses.add(response);
      },
      emitEvent: (event, payload) async {
        emittedEvents.add((event: event, payload: payload));
      },
      hasReceivedCapabilities: () => true,
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
    });
  });

  group('rpc.discover special-case', () {
    test('returns the OpenRPC document without invoking the dispatcher', () async {
      // Wrap in a frame so handleRequest's decode step succeeds.
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
        localSignatureRequired: () => false,
      );
      final wire = await frameCodec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: const {
          'jsonrpc': '2.0',
          'id': 'disc-1',
          'method': 'rpc.discover',
        },
      );

      await handler.handleRequest(wire);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.id, 'disc-1');
      expect(response.result, isA<Map<String, dynamic>>());
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

  group('handleBatchRequest', () {
    test('returns invalidRequest for empty batch', () async {
      await handler.handleBatchRequest([]);

      expect(emittedResponses, hasLength(1));
      final response = emittedResponses.single as RpcResponse;
      expect(response.error?.code, RpcErrorCode.invalidRequest);
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
        localSignatureRequired: () => false,
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
        openRpcDocumentLoader: OpenRpcDocumentLoader(
          assetLoader: (_) async => '{"openrpc":"1.3.2","info":{"title":"t","version":"1"},"methods":[]}',
          fileLoader: (_) async => throw StateError('unused'),
          cwdProvider: () => '.',
        ),
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
      expect(data['reason'], 'protocol_not_ready');
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
}
