import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/rpc_batch_negotiation.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/rpc_request_guard.dart';
import 'package:plug_agente/infrastructure/external_services/transport/authorization_decision_logger.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_batch_inbound_handler.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_request_schema_validator.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class _MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class _MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class _MockStreamingDatabaseGateway extends Mock implements IStreamingDatabaseGateway {}

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
      QueryRequest(
        id: 'fallback',
        agentId: 'agent-1',
        query: 'SELECT 1',
        timestamp: DateTime.utc(2026),
      ),
    );
    registerFallbackValue(
      QueryResponse(
        id: 'fallback',
        requestId: 'fallback',
        agentId: 'agent-1',
        data: const [],
        timestamp: DateTime.utc(2026),
      ),
    );
    registerFallbackValue(
      const RpcRequest(jsonrpc: '2.0', method: 'sql.execute', id: 'fallback'),
    );
    registerFallbackValue(const TransportLimits());
  });

  late _MockFeatureFlags featureFlags;
  late _MockDatabaseGateway gateway;
  late _MockQueryNormalizerService normalizer;
  late InMemoryIdempotencyStore idempotencyStore;
  late RpcMethodDispatcher dispatcher;
  late ProtocolConfig protocol;
  late List<dynamic> emittedResponses;
  late RpcBatchInboundHandler batchHandler;

  const sharedIdempotencyKey = 'shared-batch-key';

  RpcBatchInboundHandler createBatchHandler() {
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
  }

  setUp(() {
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
    when(() => featureFlags.enableSocketDeliveryGuarantees).thenReturn(false);
    when(() => featureFlags.enableSocketNotificationsContract).thenReturn(true);
    when(() => featureFlags.enableSocketBatchStrictValidation).thenReturn(false);
    when(() => featureFlags.enablePayloadSigning).thenReturn(false);
    when(() => featureFlags.requireIncomingPayloadSignatures).thenReturn(false);
    when(() => featureFlags.enableParallelJsonRpcBatchDispatch).thenReturn(true);
    when(() => featureFlags.enableSocketIdempotency).thenReturn(true);
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    when(() => featureFlags.enableClientTokenPolicyIntrospection).thenReturn(true);
    when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(false);
    when(() => featureFlags.enableSocketStreamingChunks).thenReturn(false);
    when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(false);
    when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => featureFlags.enableDashboardSqlInvestigationFeed).thenReturn(false);

    gateway = _MockDatabaseGateway();
    normalizer = _MockQueryNormalizerService();
    idempotencyStore = InMemoryIdempotencyStore();

    final getClientTokenPolicy = _MockGetClientTokenPolicy();
    when(() => getClientTokenPolicy.call(any())).thenAnswer(
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

    dispatcher = RpcMethodDispatcher(
      databaseGateway: gateway,
      healthService: HealthService(
        metricsCollector: MetricsCollector(),
        gateway: gateway,
      ),
      normalizerService: normalizer,
      uuid: const Uuid(),
      authorizeSqlOperation: _MockAuthorizeSqlOperation(),
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
      featureFlags: featureFlags,
      idempotencyStore: idempotencyStore,
      streamingGateway: _MockStreamingDatabaseGateway(),
    );

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
    batchHandler = createBatchHandler();
  });

  group('parallel batch dispatch with idempotency', () {
    test(
      'should deduplicate in-flight duplicate idempotency keys during parallel dispatch',
      () async {
        var executeQueryCalls = 0;
        final unblockQuery = Completer<void>();

        when(() => gateway.executeQuery(any())).thenAnswer((invocation) async {
          executeQueryCalls++;
          await unblockQuery.future;
          final request = invocation.positionalArguments[0] as QueryRequest;
          return Success(
            QueryResponse(
              id: request.id,
              requestId: request.sourceRpcRequestId ?? request.id,
              agentId: 'agent-1',
              data: const [
                {'value': 1},
              ],
              timestamp: DateTime.utc(2026, 5, 23),
            ),
          );
        });
        when(() => normalizer.normalize(any())).thenAnswer((invocation) {
          return invocation.positionalArguments[0] as QueryResponse;
        });

        final handleFuture = batchHandler.handleBatchRequest([
          _batchItem(
            id: 'sql-1',
            method: 'sql.execute',
            params: {
              'sql': 'SELECT 1',
              'idempotency_key': sharedIdempotencyKey,
            },
          ),
          _batchItem(
            id: 'sql-2',
            method: 'sql.execute',
            params: {
              'sql': 'SELECT 1',
              'idempotency_key': sharedIdempotencyKey,
            },
          ),
        ]);

        await pumpEventQueue();
        expect(executeQueryCalls, 1);

        unblockQuery.complete();
        await handleFuture;

        expect(executeQueryCalls, 1);
        expect(emittedResponses, hasLength(1));

        final responses = emittedResponses.single as List<RpcResponse>;
        expect(responses, hasLength(2));
        expect(responses.map((response) => response.id), ['sql-1', 'sql-2']);
        expect(responses.every((response) => response.isSuccess), isTrue);
        expect(
          responses.map((response) => (response.result as Map<String, dynamic>)['rows']),
          everyElement(
            [
              {'value': 1},
            ],
          ),
        );
      },
    );

    test(
      'should return cached idempotency response for later batch item after leader completes',
      () async {
        when(() => gateway.executeQuery(any())).thenAnswer((invocation) async {
          final request = invocation.positionalArguments[0] as QueryRequest;
          return Success(
            QueryResponse(
              id: request.id,
              requestId: request.sourceRpcRequestId ?? request.id,
              agentId: 'agent-1',
              data: const [
                {'value': 42},
              ],
              timestamp: DateTime.utc(2026, 5, 23),
            ),
          );
        });
        when(() => normalizer.normalize(any())).thenAnswer((invocation) {
          return invocation.positionalArguments[0] as QueryResponse;
        });

        await batchHandler.handleBatchRequest([
          _batchItem(
            id: 'sql-leader',
            method: 'sql.execute',
            params: {
              'sql': 'SELECT 42',
              'idempotency_key': sharedIdempotencyKey,
            },
          ),
        ]);
        emittedResponses.clear();

        await batchHandler.handleBatchRequest([
          _batchItem(
            id: 'sql-follower',
            method: 'sql.execute',
            params: {
              'sql': 'SELECT 42',
              'idempotency_key': sharedIdempotencyKey,
            },
          ),
        ]);

        verify(() => gateway.executeQuery(any())).called(1);

        final responses = emittedResponses.single as List<RpcResponse>;
        expect(responses.single.id, 'sql-follower');
        expect(responses.single.isSuccess, isTrue);
        expect(
          (responses.single.result as Map<String, dynamic>)['rows'],
          [
            {'value': 42},
          ],
        );
      },
    );
  });
}
