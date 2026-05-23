import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_batch_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_rpc_request_dispatcher.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_batch_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockDispatcher extends Mock implements IRpcRequestDispatcher {}

class _MockRequestGuard extends Mock implements RpcRequestGuard {}

Map<String, dynamic> _batchItem({
  required String id,
  required String method,
  Map<String, dynamic>? params,
}) {
  return {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    'params': ?params,
  };
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const RpcRequest(jsonrpc: '2.0', method: 'agent.getHealth', id: 'fallback'),
    );
    registerFallbackValue(const TransportLimits());
    registerFallbackValue(
      const RpcRequest(jsonrpc: '2.0', method: 'agent.getHealth', id: 'guard-fallback'),
    );
  });

  late _MockFeatureFlags featureFlags;
  late _MockDispatcher dispatcher;
  late ProtocolConfig protocol;
  late List<dynamic> emittedResponses;
  late RpcBatchInboundHandler batchHandler;

  setUp(() {
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
    when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(false);
    when(() => featureFlags.enableSocketNotificationsContract).thenReturn(true);
    when(() => featureFlags.enableSocketBatchStrictValidation).thenReturn(false);
    when(() => featureFlags.enablePayloadSigning).thenReturn(false);
    when(() => featureFlags.requireIncomingPayloadSignatures).thenReturn(false);
    when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(false);
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    when(() => featureFlags.enableClientTokenPolicyIntrospection).thenReturn(false);
    when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(false);

    dispatcher = _MockDispatcher();
    protocol = const ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'none',
      negotiatedExtensions: {'orderedBatchResponses': true},
    );
    emittedResponses = [];

    final summarizer = PayloadLogSummarizer(thresholdBytes: 8192);
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

    batchHandler = RpcBatchInboundHandler(
      featureFlags: featureFlags,
      protocolProvider: () => protocol,
      logSummarizer: summarizer,
      responsePreparer: preparer,
      authorizationDecisionLogger: authzLogger,
      dispatcher: dispatcher,
      requestGuard: RpcRequestGuard(maxRequestsPerWindow: 1000),
      schemaValidator: const RpcRequestSchemaValidator(),
      agentIdProvider: () => 'agent-1',
      emitInboundRpcResponse: (response, {methodsById = const {}}) async {
        emittedResponses.add(response);
      },
      emitEvent: (_, _) async {},
      sendSchemaValidationError: (_, _, _, {errorReason}) async {},
      validateBatchRequestJsonSchemasOrEmit: (_) async => true,
      hasNullIdCompatibilityViolation: (_) => false,
    );
  });

  group('parallel JSON-RPC batch dispatch', () {
    test('should stay sequential when feature flag is disabled', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(false);
      final dispatchStarted = <String>[];
      final unblockDispatch = Completer<void>();

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        dispatchStarted.add(request.id.toString());
        await unblockDispatch.future;
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'ok': request.id});
      });

      final handleFuture = batchHandler.handleBatchRequest([
        _batchItem(id: 'health-1', method: 'agent.getHealth'),
        _batchItem(id: 'health-2', method: 'agent.getHealth'),
      ]);

      await pumpEventQueue();
      expect(dispatchStarted, ['health-1']);
      expect(dispatchStarted, hasLength(1));

      unblockDispatch.complete();
      await handleFuture;

      expect(dispatchStarted, ['health-1', 'health-2']);
    });

    test('should dispatch homogeneous whitelisted batch in parallel when flag is enabled', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      final inFlight = <String>[];
      final maxInFlight = <int>[0];
      final unblockDispatch = Completer<void>();

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        inFlight.add(request.id.toString());
        maxInFlight.add(inFlight.length);
        await unblockDispatch.future;
        inFlight.remove(request.id.toString());
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'ok': request.id});
      });

      final handleFuture = batchHandler.handleBatchRequest([
        _batchItem(id: 'health-1', method: 'agent.getHealth'),
        _batchItem(id: 'health-2', method: 'agent.getHealth'),
        _batchItem(id: 'health-3', method: 'agent.getHealth'),
      ]);

      await pumpEventQueue();
      expect(maxInFlight.reduce((left, right) => left > right ? left : right), greaterThan(1));

      unblockDispatch.complete();
      await handleFuture;

      expect(emittedResponses, hasLength(1));
      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses.map((response) => response.id), ['health-1', 'health-2', 'health-3']);
      verify(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).called(3);
    });

    test('should stay sequential for mixed-method batches even when flag is enabled', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      final dispatchStarted = <String>[];
      final unblockDispatch = Completer<void>();

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        dispatchStarted.add(request.id.toString());
        await unblockDispatch.future;
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'ok': request.id});
      });

      final handleFuture = batchHandler.handleBatchRequest([
        _batchItem(id: 'health-1', method: 'agent.getHealth'),
        _batchItem(id: 'profile-1', method: 'agent.getProfile'),
      ]);

      await pumpEventQueue();
      expect(dispatchStarted, ['health-1']);

      unblockDispatch.complete();
      await handleFuture;

      expect(dispatchStarted, ['health-1', 'profile-1']);
    });

    test('should stay sequential for write-containing batches even when flag is enabled', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      final dispatchStarted = <String>[];
      final unblockDispatch = Completer<void>();

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        dispatchStarted.add(request.id.toString());
        await unblockDispatch.future;
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'ok': request.id});
      });

      final handleFuture = batchHandler.handleBatchRequest([
        _batchItem(id: 'health-1', method: 'agent.getHealth'),
        _batchItem(
          id: 'sql-1',
          method: 'sql.execute',
          params: {'sql': 'SELECT 1'},
        ),
      ]);

      await pumpEventQueue();
      expect(dispatchStarted, ['health-1']);

      unblockDispatch.complete();
      await handleFuture;

      expect(dispatchStarted, ['health-1', 'sql-1']);
    });

    test('should evaluate RpcRequestGuard for all items before parallel dispatch starts', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      final guard = _MockRequestGuard();
      var guardEvaluations = 0;
      var dispatchInvocations = 0;

      when(() => guard.evaluate(any())).thenAnswer((_) {
        guardEvaluations++;
        expect(dispatchInvocations, 0);
        return RpcRequestGuardResult.allow;
      });

      final summarizer = PayloadLogSummarizer(thresholdBytes: 8192);
      final preparer = RpcResponsePreparer(
        featureFlags: featureFlags,
        logSummarizer: summarizer,
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => protocol,
        usesBinaryTransport: () => true,
        agentIdProvider: () => 'agent-1',
      );
      final guardedHandler = RpcBatchInboundHandler(
        featureFlags: featureFlags,
        protocolProvider: () => protocol,
        logSummarizer: summarizer,
        responsePreparer: preparer,
        authorizationDecisionLogger: AuthorizationDecisionLogger(
          featureFlags: featureFlags,
          logMessage: (_, _, _) {},
          agentIdProvider: () => 'agent-1',
          onTokenRefreshRequested: () {},
        ),
        dispatcher: dispatcher,
        requestGuard: guard,
        schemaValidator: const RpcRequestSchemaValidator(),
        agentIdProvider: () => 'agent-1',
        emitInboundRpcResponse: (response, {methodsById = const {}}) async {
          emittedResponses.add(response);
        },
        emitEvent: (_, _) async {},
        sendSchemaValidationError: (_, _, _, {errorReason}) async {},
        validateBatchRequestJsonSchemasOrEmit: (_) async => true,
        hasNullIdCompatibilityViolation: (_) => false,
      );

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        dispatchInvocations++;
        final request = invocation.positionalArguments[0] as RpcRequest;
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'ok': request.id});
      });

      await guardedHandler.handleBatchRequest([
        _batchItem(id: 'health-1', method: 'agent.getHealth'),
        _batchItem(id: 'health-2', method: 'agent.getHealth'),
      ]);

      expect(guardEvaluations, 2);
      expect(dispatchInvocations, 2);
      verify(() => guard.evaluate(any())).called(2);
    });

    test('should preserve response order by index after parallel dispatch', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        final id = request.id.toString();
        final delayMs = switch (id) {
          'health-1' => 30,
          'health-2' => 10,
          'health-3' => 20,
          _ => 0,
        };
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'id': id});
      });

      await batchHandler.handleBatchRequest([
        _batchItem(id: 'health-1', method: 'agent.getHealth'),
        _batchItem(id: 'health-2', method: 'agent.getHealth'),
        _batchItem(id: 'health-3', method: 'agent.getHealth'),
      ]);

      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses.map((response) => response.id), ['health-1', 'health-2', 'health-3']);
    });

    test('should cap parallel dispatch concurrency at configured maximum', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      final inFlight = <String>[];
      final maxInFlight = <int>[0];
      final unblockDispatch = Completer<void>();

      when(
        () => dispatcher.dispatch(
          any(),
          any(),
          clientToken: any(named: 'clientToken'),
          limits: any(named: 'limits'),
          negotiatedExtensions: any(named: 'negotiatedExtensions'),
        ),
      ).thenAnswer((invocation) async {
        final request = invocation.positionalArguments[0] as RpcRequest;
        inFlight.add(request.id.toString());
        maxInFlight.add(inFlight.length);
        await unblockDispatch.future;
        inFlight.remove(request.id.toString());
        return RpcResponse.success(id: request.id, result: <String, dynamic>{'ok': request.id});
      });

      final batch = List<Map<String, dynamic>>.generate(
        RpcBatchConstants.maxParallelJsonRpcBatchDispatchConcurrency + 2,
        (index) => _batchItem(id: 'health-$index', method: 'agent.getHealth'),
      );

      final handleFuture = batchHandler.handleBatchRequest(batch);
      await pumpEventQueue();

      expect(
        maxInFlight.reduce((left, right) => left > right ? left : right),
        RpcBatchConstants.maxParallelJsonRpcBatchDispatchConcurrency,
      );

      unblockDispatch.complete();
      await handleFuture;
    });
  });
}
