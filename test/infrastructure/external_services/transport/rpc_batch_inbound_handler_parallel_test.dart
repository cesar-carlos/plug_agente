import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/rpc_batch_constants.dart';
import 'package:plug_agente/core/constants/rpc_batch_negotiation.dart';
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
  var testPoolSize = ConnectionConstants.defaultPoolSize;

  RpcBatchInboundHandler createBatchHandler({
    RpcRequestGuard? requestGuard,
  }) {
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

    return RpcBatchInboundHandler(
      featureFlags: featureFlags,
      protocolProvider: () => protocol,
      logSummarizer: summarizer,
      responsePreparer: preparer,
      authorizationDecisionLogger: authzLogger,
      dispatcher: dispatcher,
      requestGuard: requestGuard ?? RpcRequestGuard(maxRequestsPerWindow: 1000),
      schemaValidator: const RpcRequestSchemaValidator(),
      agentIdProvider: () => 'agent-1',
      emitInboundRpcResponse: (response, {methodsById = const {}}) async {
        emittedResponses.add(response);
      },
      emitEvent: (_, _) async {},
      sendSchemaValidationError: (_, _, _, {errorReason, method}) async {},
      validateBatchRequestJsonSchemasOrEmit: (_) async => true,
      hasNullIdCompatibilityViolation: (_) => false,
      poolSizeProvider: () => testPoolSize,
    );
  }

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
    protocol = ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'none',
      negotiatedExtensions: {
        'orderedBatchResponses': true,
        'parallelBatchDispatch': ParallelBatchDispatchNegotiation.agentAdvertisement(enabled: true),
      },
    );
    emittedResponses = [];
    testPoolSize = ConnectionConstants.defaultPoolSize;
    batchHandler = createBatchHandler();
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

    test('should dispatch mixed whitelist batch in parallel when flag is enabled', () async {
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
        _batchItem(id: 'profile-1', method: 'agent.getProfile'),
      ]);

      await pumpEventQueue();
      expect(maxInFlight.reduce((left, right) => left > right ? left : right), greaterThan(1));

      unblockDispatch.complete();
      await handleFuture;

      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses.map((response) => response.id), ['health-1', 'profile-1']);
    });

    test('should stay sequential when parallelBatchDispatch is not negotiated', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      protocol = const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
        negotiatedExtensions: {'orderedBatchResponses': true},
      );
      batchHandler = createBatchHandler();

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

      unblockDispatch.complete();
      await handleFuture;

      expect(dispatchStarted, ['health-1', 'health-2']);
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

      final guardedHandler = createBatchHandler(requestGuard: guard);

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

    test('should dispatch homogeneous SELECT-only sql.execute batch in parallel when flag is enabled', () async {
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
        _batchItem(id: 'sql-1', method: 'sql.execute', params: {'sql': 'SELECT 1'}),
        _batchItem(id: 'sql-2', method: 'sql.execute', params: {'sql': 'SELECT 2'}),
        _batchItem(id: 'sql-3', method: 'sql.execute', params: {'sql': 'WITH cte AS (SELECT 3) SELECT * FROM cte'}),
      ]);

      await pumpEventQueue();
      expect(maxInFlight.reduce((left, right) => left > right ? left : right), greaterThan(1));

      unblockDispatch.complete();
      await handleFuture;

      final responses = emittedResponses.single as List<RpcResponse>;
      expect(responses.map((response) => response.id), ['sql-1', 'sql-2', 'sql-3']);
    });

    test(
      'should stay sequential for homogeneous sql.execute batch containing write SQL when flag is enabled',
      () async {
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
          _batchItem(id: 'sql-1', method: 'sql.execute', params: {'sql': 'SELECT 1'}),
          _batchItem(id: 'sql-2', method: 'sql.execute', params: {'sql': 'INSERT INTO t VALUES (1)'}),
        ]);

        await pumpEventQueue();
        expect(dispatchStarted, ['sql-1']);

        unblockDispatch.complete();
        await handleFuture;

        expect(dispatchStarted, ['sql-1', 'sql-2']);
      },
    );

    test('should stay sequential for SELECT-only sql.execute batch when flag is disabled', () async {
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
        _batchItem(id: 'sql-1', method: 'sql.execute', params: {'sql': 'SELECT 1'}),
        _batchItem(id: 'sql-2', method: 'sql.execute', params: {'sql': 'SELECT 2'}),
      ]);

      await pumpEventQueue();
      expect(dispatchStarted, ['sql-1']);

      unblockDispatch.complete();
      await handleFuture;

      expect(dispatchStarted, ['sql-1', 'sql-2']);
    });

    test('should evaluate RpcRequestGuard for all sql.execute items before parallel dispatch starts', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      final guard = _MockRequestGuard();
      var guardEvaluations = 0;
      var dispatchInvocations = 0;

      when(() => guard.evaluate(any())).thenAnswer((_) {
        guardEvaluations++;
        expect(dispatchInvocations, 0);
        return RpcRequestGuardResult.allow;
      });

      final guardedHandler = createBatchHandler(requestGuard: guard);

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
        _batchItem(id: 'sql-1', method: 'sql.execute', params: {'sql': 'SELECT 1'}),
        _batchItem(id: 'sql-2', method: 'sql.execute', params: {'sql': 'SELECT 2'}),
      ]);

      expect(guardEvaluations, 2);
      expect(dispatchInvocations, 2);
      verify(() => guard.evaluate(any())).called(2);
    });

    test('should cap sql.execute parallel dispatch concurrency using pool-aware limit', () async {
      when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
      testPoolSize = 4;
      final expectedConcurrency = RpcBatchConstants.parallelJsonRpcBatchSqlExecuteConcurrencyForPoolSize(
        testPoolSize,
      );
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
        expectedConcurrency + 2,
        (index) => _batchItem(
          id: 'sql-$index',
          method: 'sql.execute',
          params: {'sql': 'SELECT $index'},
        ),
      );

      final handleFuture = batchHandler.handleBatchRequest(batch);
      await pumpEventQueue();

      expect(
        maxInFlight.reduce((left, right) => left > right ? left : right),
        expectedConcurrency,
      );

      unblockDispatch.complete();
      await handleFuture;
    });
  });

  group('rpc:batch_ack delivery guarantee (B3)', () {
    test('should emit rpc:batch_ack with request ids when enableSocketDeliveryGuarantees is true', () async {
      when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(true);

      final emittedEvents = <({String event, dynamic payload})>[];
      final trackingHandler = RpcBatchInboundHandler(
        featureFlags: featureFlags,
        protocolProvider: () => protocol,
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
        requestGuard: RpcRequestGuard(maxRequestsPerWindow: 1000),
        schemaValidator: const RpcRequestSchemaValidator(),
        agentIdProvider: () => 'agent-1',
        emitInboundRpcResponse: (response, {methodsById = const {}}) async {
          emittedResponses.add(response);
        },
        emitEvent: (event, payload) async {
          emittedEvents.add((event: event, payload: payload));
        },
        sendSchemaValidationError: (_, _, _, {errorReason, method}) async {},
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
      ).thenAnswer(
        (inv) async => RpcResponse.success(
          id: (inv.positionalArguments[0] as RpcRequest).id,
          result: <String, dynamic>{},
        ),
      );

      final batch = [
        _batchItem(id: 'req-1', method: 'sql.execute', params: {'sql': 'SELECT 1'}),
        _batchItem(id: 'req-2', method: 'sql.execute', params: {'sql': 'SELECT 2'}),
      ];

      await trackingHandler.handleBatchRequest(batch);

      final ackEvents = emittedEvents.where((e) => e.event == 'rpc:batch_ack').toList();
      expect(ackEvents, hasLength(1));
      final ackPayload = ackEvents.single.payload as Map<String, dynamic>;
      expect(ackPayload['request_ids'], containsAll(['req-1', 'req-2']));
      expect(ackPayload.containsKey('received_at'), isTrue);
    });

    test('should NOT emit rpc:batch_ack when enableSocketDeliveryGuarantees is false', () async {
      when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(false);

      final emittedEvents = <({String event, dynamic payload})>[];
      final trackingHandler = RpcBatchInboundHandler(
        featureFlags: featureFlags,
        protocolProvider: () => protocol,
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
        requestGuard: RpcRequestGuard(maxRequestsPerWindow: 1000),
        schemaValidator: const RpcRequestSchemaValidator(),
        agentIdProvider: () => 'agent-1',
        emitInboundRpcResponse: (response, {methodsById = const {}}) async {
          emittedResponses.add(response);
        },
        emitEvent: (event, payload) async {
          emittedEvents.add((event: event, payload: payload));
        },
        sendSchemaValidationError: (_, _, _, {errorReason, method}) async {},
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
      ).thenAnswer(
        (inv) async => RpcResponse.success(
          id: (inv.positionalArguments[0] as RpcRequest).id,
          result: <String, dynamic>{},
        ),
      );

      await trackingHandler.handleBatchRequest([
        _batchItem(id: 'req-1', method: 'sql.execute', params: {'sql': 'SELECT 1'}),
      ]);

      expect(emittedEvents.where((e) => e.event == 'rpc:batch_ack'), isEmpty);
    });
  });
}
