import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool_factory.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import 'mock_odbc_connection_settings.dart';
import 'odbc_e2e_live_sql.dart';

class MockAgentConfigRepository extends Mock
    implements IAgentConfigRepository {}

class MockAuthorizeSqlOperation extends Mock implements AuthorizeSqlOperation {}

class MockFeatureFlags extends Mock implements FeatureFlags {}

/// Live ODBC + real [OdbcDatabaseGateway] + [RpcMethodDispatcher] for RPC E2E.
class OdbcE2eRpcHarness {
  OdbcE2eRpcHarness._({
    required this.locator,
    required this.connectionPool,
    required this.gateway,
    required this.dispatcher,
    required this.connectionString,
    required this.metrics,
    required this.featureFlags,
  });

  static odbc.ServiceLocator? _sharedLocator;
  static bool _sharedLocatorInitialized = false;

  final odbc.ServiceLocator locator;
  final IConnectionPool connectionPool;
  final IDatabaseGateway gateway;
  final RpcMethodDispatcher dispatcher;
  final String connectionString;
  final MetricsCollector metrics;

  /// Toggle streaming / cancel flags in live E2E without rebuilding the pool.
  final MockFeatureFlags featureFlags;

  static Config _configFor(String dsn, OdbcE2eSqlDialect dialect) {
    final driverName = switch (dialect) {
      OdbcE2eSqlDialect.sqlAnywhere => 'SQL Anywhere',
      OdbcE2eSqlDialect.sqlServer => 'SQL Server',
      OdbcE2eSqlDialect.postgresql => 'PostgreSQL',
    };
    final now = DateTime.utc(2024);
    return Config(
      id: 'e2e-live',
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
    OdbcE2eSqlDialect dialect, {
    MockOdbcConnectionSettings? connectionSettings,
    bool useSharedLocator = false,
  }) async {
    final locator = useSharedLocator
        ? await _acquireSharedLocator()
        : (odbc.ServiceLocator()..initialize(useAsync: true));
    if (locator == null) {
      return null;
    }
    final service = locator.asyncService;
    if (!useSharedLocator) {
      final init = await service.initialize();
      if (init.isError()) {
        locator.shutdown();
        return null;
      }
    }

    final configRepo = MockAgentConfigRepository();
    final cfg = _configFor(dsn, dialect);
    // ignore: unnecessary_lambdas
    when(() => configRepo.getCurrentConfig()).thenAnswer(
      (_) => Future.value(Success(cfg)),
    );

    final settings = connectionSettings ?? MockOdbcConnectionSettings();
    final retry = RetryManager();
    final metrics = MetricsCollector()..clear();
    final pool = createOdbcConnectionPool(
      service,
      settings,
      metricsCollector: metrics,
    );
    final gateway = OdbcDatabaseGateway(
      configRepo,
      service,
      pool,
      retry,
      metrics,
      settings,
    );

    final streamingGateway = OdbcStreamingGateway(
      service,
      settings,
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
    when(() => featureFlags.enableSocketIdempotency).thenReturn(false);
    when(() => featureFlags.enableSocketTimeoutByStage).thenReturn(false);
    when(() => featureFlags.enableSocketCancelMethod).thenReturn(true);
    when(() => featureFlags.enableSocketStreamingFromDb).thenReturn(true);
    when(() => featureFlags.enableSocketStreamingChunks).thenReturn(true);

    final dispatcher = RpcMethodDispatcher(
      databaseGateway: gateway,
      normalizerService: normalizer,
      uuid: const Uuid(),
      authorizeSqlOperation: authorize,
      featureFlags: featureFlags,
      configRepository: configRepo,
      streamingGateway: streamingGateway,
      dispatchMetrics: RpcDispatchMetricsCollector(metrics),
    );

    return OdbcE2eRpcHarness._(
      locator: locator,
      connectionPool: pool,
      gateway: gateway,
      dispatcher: dispatcher,
      connectionString: dsn,
      metrics: metrics,
      featureFlags: featureFlags,
    );
  }

  static Future<odbc.ServiceLocator?> _acquireSharedLocator() async {
    final existing = _sharedLocator;
    if (existing != null && _sharedLocatorInitialized) {
      return existing;
    }

    final locator =
        existing ?? (odbc.ServiceLocator()..initialize(useAsync: true));
    final init = await locator.asyncService.initialize();
    if (init.isError()) {
      locator.shutdown();
      if (identical(locator, _sharedLocator)) {
        _sharedLocator = null;
      }
      _sharedLocatorInitialized = false;
      return null;
    }

    _sharedLocator = locator;
    _sharedLocatorInitialized = true;
    return locator;
  }

  static Future<void> shutdownSharedLocator() async {
    final locator = _sharedLocator;
    if (locator == null) {
      return;
    }
    locator.shutdown();
    _sharedLocator = null;
    _sharedLocatorInitialized = false;
  }

  Future<void> shutdown({bool shutdownLocator = true}) async {
    await connectionPool.closeAll();
    if (shutdownLocator) {
      locator.shutdown();
    }
  }
}
