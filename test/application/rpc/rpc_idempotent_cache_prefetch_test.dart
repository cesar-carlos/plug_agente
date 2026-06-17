import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/rpc_method_dispatcher_test_support.dart';

class _MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class _MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class _MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class _MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockIdempotencyStore extends Mock implements IIdempotencyStore {}

class _MockStreamingDatabaseGateway extends Mock implements IStreamingDatabaseGateway {}

void main() {
  group('RPC idempotent cache prefetch', () {
    late _MockDatabaseGateway gateway;
    late _MockQueryNormalizerService normalizer;
    late _MockFeatureFlags featureFlags;
    late _MockIdempotencyStore store;
    late RpcMethodDispatcher dispatcher;

    setUpAll(() {
      registerFallbackValue(
        QueryRequest(
          id: 'test',
          agentId: 'agent-1',
          query: 'SELECT 1',
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
      registerFallbackValue(RpcResponse.success(id: 'req-1', result: const <String, Object?>{}));
      registerFallbackValue(const Duration(seconds: 7));
    });

    setUp(() {
      gateway = _MockDatabaseGateway();
      normalizer = _MockQueryNormalizerService();
      featureFlags = _MockFeatureFlags();
      store = _MockIdempotencyStore();

      when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
      when(() => featureFlags.enableSocketIdempotency).thenReturn(true);
      when(() => featureFlags.enableSocketStreamingChunks).thenReturn(false);
      when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(false);
      when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => featureFlags.enableSocketCancelMethod).thenReturn(false);
      when(() => featureFlags.enableDashboardSqlInvestigationFeed).thenReturn(false);
      when(() => featureFlags.enableAgentActionRemoteAudit).thenReturn(false);

      when(() => store.getRecord(any())).thenAnswer((_) async => null);
      when(
        () => store.set(
          any(),
          any(),
          any(),
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).thenAnswer((_) async {});

      when(
        () => gateway.executeQuery(
          any(),
          timeout: any(named: 'timeout'),
          database: any(named: 'database'),
        ),
      ).thenAnswer(
        (_) async => Success(
          QueryResponse(
            id: 'exec-1',
            requestId: 'req-1',
            agentId: 'agent-1',
            data: const [
              {'x': 1},
            ],
            timestamp: DateTime.now(),
          ),
        ),
      );
      when(() => normalizer.normalizeAsync(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as QueryResponse,
      );

      dispatcher = RpcMethodDispatcher(
        streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
        databaseGateway: gateway,
        healthService: HealthService(
          metricsCollector: MetricsCollector(),
          gateway: gateway,
        ),
        normalizerService: normalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: _MockAuthorizeSqlOperation(),
        getClientTokenPolicy: _MockGetClientTokenPolicy(),
        getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
        featureFlags: featureFlags,
        idempotencyStore: store,
        streamingGateway: _MockStreamingDatabaseGateway(),
      );
    });

    test('should read idempotency store only once on cache miss', () async {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        params: <String, dynamic>{
          'sql': 'SELECT 1',
          'idempotency_key': 'key-abc',
        },
      );

      final response = await dispatcher.dispatch(request, 'agent-1');

      expect(response.isSuccess, isTrue);
      verify(() => store.getRecord('sql.execute:key-abc')).called(1);
      verify(
        () => store.set(
          'sql.execute:key-abc',
          any(),
          any(),
          requestFingerprint: any(named: 'requestFingerprint'),
        ),
      ).called(1);
    });
  });
}
