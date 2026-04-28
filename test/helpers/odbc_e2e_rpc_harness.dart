import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import 'mock_odbc_connection_settings.dart';
import 'odbc_e2e_coverage_sql.dart';

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

class MockAuthorizationPolicyResolver extends Mock implements IAuthorizationPolicyResolver {}

/// Live ODBC + real [OdbcDatabaseGateway] + [RpcMethodDispatcher] for RPC E2E.
class OdbcE2eRpcHarness {
  OdbcE2eRpcHarness._({
    required this.locator,
    required this.connectionPool,
    required this.gateway,
    required this.dispatcher,
    required this.connectionString,
    required this.metrics,
  });

  final odbc.ServiceLocator locator;
  final IConnectionPool connectionPool;
  final IDatabaseGateway gateway;
  final RpcMethodDispatcher dispatcher;
  final String connectionString;
  final MetricsCollector metrics;

  static Config _configFor(String dsn, OdbcE2eSqlDialect dialect) {
    final driverName = switch (dialect) {
      OdbcE2eSqlDialect.sqlAnywhere => 'SQL Anywhere',
      OdbcE2eSqlDialect.sqlServer => 'SQL Server',
      OdbcE2eSqlDialect.postgresql => 'PostgreSQL',
    };
    final now = DateTime.utc(2024);
    return Config(
      id: 'e2e-coverage',
      driverName: driverName,
      odbcDriverName: '',
      connectionString: dsn,
      username: 'e2e',
      databaseName: 'e2e',
      host: 'localhost',
      port: 0,
      createdAt: now,
      updatedAt: now,
      agentId: 'e2e-agent',
    );
  }

  /// Returns null when ODBC failed to initialize.
  static Future<OdbcE2eRpcHarness?> open(
    String dsn,
    OdbcE2eSqlDialect dialect,
  ) async {
    final locator = odbc.ServiceLocator()..initialize(useAsync: true);
    final service = locator.asyncService;
    final init = await service.initialize();
    if (init.isError()) {
      locator.shutdown();
      return null;
    }

    final configRepo = MockAgentConfigRepository();
    final cfg = _configFor(dsn, dialect);
    // ignore: unnecessary_lambdas
    when(() => configRepo.getCurrentConfig()).thenAnswer(
      (_) => Future.value(Success(cfg)),
    );

    final pool = OdbcConnectionPool(service, MockOdbcConnectionSettings());
    final retry = RetryManager();
    final metrics = MetricsCollector()..clear();
    final gateway = OdbcDatabaseGateway(
      configRepo,
      service,
      pool,
      retry,
      metrics,
      MockOdbcConnectionSettings(),
    );

    final normalizer = QueryNormalizerService(QueryNormalizer());
    final authorize = MockAuthorizeSqlOperation();
    when(
      () => authorize.call(
        token: any(named: 'token'),
        sql: any(named: 'sql'),
        requestId: any(named: 'requestId'),
        method: any(named: 'method'),
      ),
    ).thenAnswer((_) async => const Success(unit));

    final featureFlags = MockFeatureFlags();
    when(() => featureFlags.enableClientTokenAuthorization).thenReturn(false);
    when(() => featureFlags.enableClientTokenPolicyIntrospection).thenReturn(true);
    when(() => featureFlags.enableSocketIdempotency).thenReturn(false);
    when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => featureFlags.enableSocketCancelMethod).thenReturn(false);
    when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(false);
    when(() => featureFlags.enableSocketStreamingChunks).thenReturn(false);

    final policyResolver = MockAuthorizationPolicyResolver();
    when(() => policyResolver.resolvePolicy(any())).thenAnswer(
      (_) async => const Success(
        ClientTokenPolicy(
          clientId: 'e2e',
          allTables: true,
          allViews: true,
          allPermissions: true,
          rules: [],
        ),
      ),
    );
    final getClientTokenPolicy = GetClientTokenPolicy(policyResolver);

    final dispatcher = RpcMethodDispatcher(
      databaseGateway: gateway,
      healthService: HealthService(
        metricsCollector: metrics,
        gateway: gateway,
      ),
      normalizerService: normalizer,
      uuid: const Uuid(),
      authorizeSqlOperation: authorize,
      getClientTokenPolicy: getClientTokenPolicy,
      getPolicyRateLimiter: ClientTokenGetPolicyRateLimiter(maxCallsPerMinute: 0),
      featureFlags: featureFlags,
    );

    return OdbcE2eRpcHarness._(
      locator: locator,
      connectionPool: pool,
      gateway: gateway,
      dispatcher: dispatcher,
      connectionString: dsn,
      metrics: metrics,
    );
  }

  Future<void> shutdown() async {
    await connectionPool.closeAll();
    locator.shutdown();
  }
}
