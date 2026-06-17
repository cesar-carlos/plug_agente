import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/entities/bulk_insert_request.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/streaming/streaming_cancel_reason.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/rpc_method_dispatcher_test_support.dart';

class MockDatabaseGateway extends Mock implements IDatabaseGateway {}

class MockQueryNormalizerService extends Mock implements QueryNormalizerService {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockGetClientTokenPolicy extends Mock implements GetClientTokenPolicy {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockStreamingDatabaseGateway extends Mock implements IStreamingDatabaseGateway, IStreamingGatewayDiagnostics {}

class MockOdbcNativeMetricsService extends Mock implements OdbcNativeMetricsService {}

HealthService _testHealthService(IDatabaseGateway gateway) => HealthService(
  metricsCollector: MetricsCollector(),
  gateway: gateway,
);

final ClientTokenGetPolicyRateLimiter _testDisabledGetPolicyRateLimiter = ClientTokenGetPolicyRateLimiter(
  maxCallsPerMinute: 0,
);

void main() {
  setUpAll(() {
    registerFallbackValue(StreamingCancelReason.user);
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
        id: 'test',
        requestId: 'test',
        agentId: 'test',
        data: const [],
        timestamp: DateTime.now(),
      ),
    );
    registerFallbackValue(Duration.zero);
    registerFallbackValue(const Duration(seconds: 7));
    registerFallbackValue('');
    registerFallbackValue(const SqlCommand(sql: 'SELECT 1'));
    registerFallbackValue(const SqlExecutionOptions());
    registerFallbackValue(
      const BulkInsertRequest(
        table: 'users',
        columns: [
          BulkInsertColumn(name: 'id', type: BulkInsertColumnType.i32),
        ],
        rows: [
          [1],
        ],
      ),
    );
  });

  group('RpcMethodDispatcher circuit breaker', () {
    late MockDatabaseGateway mockGateway;
    late MockQueryNormalizerService mockNormalizer;
    late MockStreamingDatabaseGateway mockStreamingGateway;
    late MockOdbcNativeMetricsService mockOdbcNativeMetricsService;
    late MockAuthorizeSqlOperation mockAuthorize;
    late MockGetClientTokenPolicy mockGetClientTokenPolicy;
    late MockFeatureFlags mockFeatureFlags;
    late RpcMethodDispatcher dispatcher;

    setUp(() {
      dotenv.clean();

      mockGateway = MockDatabaseGateway();
      mockNormalizer = MockQueryNormalizerService();
      mockStreamingGateway = MockStreamingDatabaseGateway();
      mockOdbcNativeMetricsService = MockOdbcNativeMetricsService();
      mockAuthorize = MockAuthorizeSqlOperation();
      mockGetClientTokenPolicy = MockGetClientTokenPolicy();

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
      mockFeatureFlags = MockFeatureFlags();
      when(() => mockFeatureFlags.enableClientTokenAuthorization).thenReturn(false);
      when(() => mockFeatureFlags.enableClientTokenPolicyIntrospection).thenReturn(true);
      when(() => mockFeatureFlags.enableSocketIdempotency).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketStreamingChunks).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketStreamingFromDb).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketTimeoutByStage).thenReturn(false);
      when(() => mockFeatureFlags.enableSocketCancelMethod).thenReturn(false);
      when(() => mockFeatureFlags.enableDashboardSqlInvestigationFeed).thenReturn(true);
      when(() => mockFeatureFlags.enableAgentActionRemoteAudit).thenReturn(false);
      when(() => mockOdbcNativeMetricsService.collectSnapshot()).thenAnswer(
        (_) async => const Success(<String, dynamic>{
          'engine': <String, dynamic>{'query_count': 0},
        }),
      );
      when(() => mockNormalizer.normalizeRows(any())).thenAnswer(
        (invocation) => invocation.positionalArguments[0] as List<Map<String, dynamic>>,
      );
      when(() => mockNormalizer.normalize(any())).thenAnswer(
        (invocation) => invocation.positionalArguments[0] as QueryResponse,
      );
      when(() => mockNormalizer.normalizeAsync(any())).thenAnswer(
        (invocation) async => invocation.positionalArguments[0] as QueryResponse,
      );
      when(mockStreamingGateway.getStreamingDiagnostics).thenReturn(
        const {
          'enabled': true,
          'active_streams': 0,
          'direct_limiter_saturated': false,
        },
      );
      when(() => mockStreamingGateway.activeStreamCount).thenReturn(0);

      dispatcher = RpcMethodDispatcher(
        streamingConnectionStringCache: rpcTestStreamingConnectionStringCache(),
        databaseGateway: mockGateway,
        healthService: _testHealthService(mockGateway),
        normalizerService: mockNormalizer,
        uuid: const Uuid(),
        authorizeSqlOperation: mockAuthorize,
        getClientTokenPolicy: mockGetClientTokenPolicy,
        getPolicyRateLimiter: _testDisabledGetPolicyRateLimiter,
        featureFlags: mockFeatureFlags,
        streamingGateway: mockStreamingGateway,
        odbcNativeMetricsService: mockOdbcNativeMetricsService,
      );
    });

    test(
      'sql.execute maps circuit breaker open to databaseConnectionFailed with retryable false',
      () async {
        const request = RpcRequest(
          jsonrpc: '2.0',
          method: 'sql.execute',
          id: 'req-cb-open',
          params: {
            'sql': 'SELECT 1',
          },
        );

        when(
          () => mockGateway.executeQuery(
            any(),
            timeout: any(named: 'timeout'),
            database: any(named: 'database'),
          ),
        ).thenAnswer(
          (_) async => Failure(
            domain.ConnectionFailure.withContext(
              message: 'Circuit breaker open for database connection',
              context: {
                'reason': OdbcContextConstants.circuitBreakerOpenReason,
                'retryable': false,
              },
            ),
          ),
        );

        final response = await dispatcher.dispatch(request, 'agent-1');

        expect(response.isError, isTrue);
        expect(response.error!.code, equals(RpcErrorCode.databaseConnectionFailed));
        final data = response.error!.data as Map<String, dynamic>;
        expect(data['retryable'], isFalse);
        expect(
          data['odbc_reason'],
          equals(OdbcContextConstants.circuitBreakerOpenReason),
        );
      },
    );
  });
}
