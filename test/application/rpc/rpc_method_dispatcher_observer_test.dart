import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/sql_observer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

void main() {
  late _FakeDatabaseGateway gateway;
  late MockFeatureFlags featureFlags;
  late SqlObserverService observerService;
  late RpcMethodDispatcher dispatcher;

  setUp(() {
    gateway = _FakeDatabaseGateway();
    featureFlags = MockFeatureFlags();
    final authorizeSqlOperation = MockAuthorizeSqlOperation();
    final getClientTokenPolicy = MockGetClientTokenPolicy();
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => getClientTokenPolicy.call(any())).thenAnswer(
      (_) async => const Success(
        ClientTokenPolicy(
          clientId: 'client-1',
          allTables: true,
          allViews: true,
          allPermissions: true,
          rules: [],
        ),
      ),
    );
    observerService = SqlObserverService(
      databaseGateway: gateway,
      normalizerService: QueryNormalizerService(QueryNormalizer()),
      uuid: const Uuid(),
      authorizeSqlOperation: authorizeSqlOperation,
      featureFlags: featureFlags,
    );
    dispatcher = RpcMethodDispatcher(
      databaseGateway: gateway,
      healthService: HealthService(
        metricsCollector: MetricsCollector(),
        gateway: gateway,
      ),
      normalizerService: QueryNormalizerService(QueryNormalizer()),
      uuid: const Uuid(),
      authorizeSqlOperation: authorizeSqlOperation,
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(
        maxCallsPerMinute: 0,
      ),
      featureFlags: featureFlags,
      sqlObserverService: observerService,
    );
  });

  tearDown(() {
    observerService.clearSession();
  });

  test('should dispatch observer.register, list and unregister', () async {
    final register = await dispatcher.dispatch(
      const RpcRequest(
        jsonrpc: '2.0',
        method: 'observer.register',
        id: 'req-1',
        params: {
          'sql': 'SELECT 1',
          'interval_seconds': 300,
        },
      ),
      'agent-1',
      limits: const TransportLimits(maxRows: 100),
    );

    expect(register.isSuccess, isTrue);
    final registerResult = register.result as Map<String, dynamic>;
    final observerId = registerResult['observer_id'] as String;
    expect(observerId, isNotEmpty);

    final list = await dispatcher.dispatch(
      const RpcRequest(
        jsonrpc: '2.0',
        method: 'observer.list',
        id: 'req-2',
      ),
      'agent-1',
    );

    expect(list.isSuccess, isTrue);
    final listResult = list.result as Map<String, dynamic>;
    expect(listResult['observers'], isA<List<dynamic>>());
    expect(listResult['observers'] as List<dynamic>, hasLength(1));

    final unregister = await dispatcher.dispatch(
      RpcRequest(
        jsonrpc: '2.0',
        method: 'observer.unregister',
        id: 'req-3',
        params: {'observer_id': observerId},
      ),
      'agent-1',
    );

    expect(unregister.isSuccess, isTrue);
    final unregisterResult = unregister.result as Map<String, dynamic>;
    expect(unregisterResult['cancelled'], isTrue);
  });
}

final class _FakeDatabaseGateway implements IDatabaseGateway {
  @override
  Future<Result<QueryResponse>> executeQuery(
    QueryRequest request, {
    Duration? timeout,
    String? database,
  }) async {
    return Success(
      QueryResponse(
        id: 'exec-1',
        requestId: request.id,
        agentId: request.agentId,
        data: const [],
        timestamp: DateTime.now(),
      ),
    );
  }

  @override
  Future<Result<List<SqlCommandResult>>> executeBatch(
    String agentId,
    List<SqlCommand> commands, {
    String? database,
    SqlExecutionOptions options = const SqlExecutionOptions(),
    Duration? timeout,
    String? sourceRpcRequestId,
  }) async {
    return const Success(<SqlCommandResult>[]);
  }

  @override
  Future<Result<int>> executeNonQuery(
    String query,
    Map<String, dynamic>? parameters, {
    Duration? timeout,
    String? database,
  }) async {
    return const Success(0);
  }

  @override
  Future<Result<bool>> testConnection(String connectionString) async {
    return const Success(true);
  }
}
