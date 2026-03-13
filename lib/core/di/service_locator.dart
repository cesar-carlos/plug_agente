import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/compression_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/query_processing_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/services/update_service.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_for_updates.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/handle_query_request.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/noop_tray_manager_service.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/compression/gzip_compressor.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_driver_checker.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/noop_notification_service.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:plug_agente/infrastructure/settings/odbc_connection_settings.dart';
import 'package:plug_agente/infrastructure/stores/file_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_audit_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

final GetIt getIt = GetIt.instance;

odbc.ServiceLocator _odbcLocator = odbc.ServiceLocator();

/// Shutdown centralizado de todos os recursos.
///
/// Sequência de encerramento:
/// 1. Desconectar transporte (WebSocket)
/// 2. Fechar pool de conexões ODBC
/// 3. Fechar banco local (Drift)
/// 4. Encerrar worker ODBC
Future<void> shutdownApp() async {
  // 1. Desconectar transporte
  if (getIt.isRegistered<ITransportClient>()) {
    final transport = getIt<ITransportClient>();
    await transport.disconnect();
  }

  // 2. Fechar pool de conexões
  if (getIt.isRegistered<IConnectionPool>()) {
    final pool = getIt<IConnectionPool>();
    await pool.closeAll();
  }

  // 3. Fechar banco local
  if (getIt.isRegistered<AppDatabase>()) {
    final db = getIt<AppDatabase>();
    await db.close();
  }

  // 4. Encerrar worker ODBC (synchronous)
  _odbcLocator.shutdown();
}

Future<void> setupDependencies({
  required RuntimeCapabilities capabilities,
}) async {
  developer.log(
    'Setting up dependencies with runtime mode: ${capabilities.mode.displayName}',
    name: 'service_locator',
    level: 800,
  );

  if (!capabilities.canRunCore) {
    throw StateError(
      'Cannot run application: ${capabilities.degradationReasons.join(", ")}',
    );
  }

  // Register capabilities globally
  getIt.registerSingleton<RuntimeCapabilities>(capabilities);

  _odbcLocator.initialize(useAsync: true);

  final prefs = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(prefs);

  final odbcSettings = OdbcConnectionSettings(prefs);
  await odbcSettings.load();
  getIt.registerSingleton<IOdbcConnectionSettings>(odbcSettings);

  final featureFlags = FeatureFlags(prefs);
  getIt.registerSingleton<FeatureFlags>(featureFlags);

  // External
  getIt
    ..registerLazySingleton<odbc.OdbcService>(() => _odbcLocator.asyncService)
    ..registerLazySingleton(GzipCompressor.new)
    ..registerLazySingleton(ConfigValidator.new)
    ..registerLazySingleton(QueryNormalizer.new)
    ..registerLazySingleton(SocketDataSource.new)
    ..registerLazySingleton(AppDatabase.new)
    ..registerLazySingleton(
      () => ClientTokenLocalDataSource(getIt<AppDatabase>()),
    )
    ..registerLazySingleton(ProtocolNegotiator.new)
    ..registerLazySingleton(ProtocolMetricsCollector.new)
    ..registerLazySingleton(AuthorizationMetricsCollector.new)
    ..registerLazySingleton<IAgentConfigRepository>(
      () => AgentConfigRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton(() => const Uuid())
    ..registerLazySingleton<IConnectionPool>(
      () => OdbcConnectionPool(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    )
    ..registerLazySingleton<IRetryManager>(() => RetryManager.instance)
    ..registerLazySingleton(() => MetricsCollector.instance)
    ..registerLazySingleton<IIdempotencyStore>(InMemoryIdempotencyStore.new)
    ..registerLazySingleton<IRevokedTokenStore>(InMemoryRevokedTokenStore.new)
    ..registerLazySingleton<ITokenAuditStore>(
      () => getIt<FeatureFlags>().enableTokenAudit
          ? FileTokenAuditStore()
          : NoopTokenAuditStore(),
    )
    ..registerLazySingleton(
      () => RpcMethodDispatcher(
        databaseGateway: getIt<IDatabaseGateway>(),
        normalizerService: getIt<QueryNormalizerService>(),
        compressionService: getIt<CompressionService>(),
        uuid: getIt<Uuid>(),
        authorizeSqlOperation: getIt<AuthorizeSqlOperation>(),
        featureFlags: getIt<FeatureFlags>(),
        configRepository: getIt<IAgentConfigRepository>(),
        idempotencyStore: getIt<IIdempotencyStore>(),
        authMetrics: getIt<AuthorizationMetricsCollector>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
      ),
    )
    ..registerLazySingleton<ITransportClient>(
      () => SocketIOTransportClientV2(
        dataSource: getIt<SocketDataSource>(),
        negotiator: getIt<ProtocolNegotiator>(),
        rpcDispatcher: getIt<RpcMethodDispatcher>(),
        featureFlags: getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton<IDatabaseGateway>(
      () => OdbcDatabaseGateway(
        getIt<IAgentConfigRepository>(),
        getIt<odbc.OdbcService>(),
        getIt<IConnectionPool>(),
        getIt<IRetryManager>(),
        getIt<MetricsCollector>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    )
    ..registerLazySingleton<IStreamingDatabaseGateway>(
      () => OdbcStreamingGateway(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    )
    ..registerLazySingleton<IOdbcDriverChecker>(OdbcDriverChecker.new)
    ..registerLazySingleton<IAuthClient>(
      () => AuthClient(DioFactory.createDio()),
    )
    ..registerLazySingleton<IAuthorizationPolicyResolver>(
      () => AuthorizationPolicyResolver(
        getIt<FeatureFlags>(),
        jwksVerifier: getIt<JwtJwksVerifier>(),
        localDataSource: getIt<ClientTokenLocalDataSource>(),
        revokedTokenStore: getIt<IRevokedTokenStore>(),
        tokenAuditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton<JwtJwksVerifier>(
      () => JwtJwksVerifier(() async {
        final jwksUrlOverride = dotenv.env['JWKS_URL']?.trim();
        if (jwksUrlOverride != null && jwksUrlOverride.isNotEmpty) {
          return JwksConfig(
            jwksUrl: jwksUrlOverride,
            issuer: dotenv.env['JWKS_ISSUER']?.trim().isNotEmpty ?? false
                ? dotenv.env['JWKS_ISSUER']
                : null,
            audience: dotenv.env['JWKS_AUDIENCE']?.trim().isNotEmpty ?? false
                ? dotenv.env['JWKS_AUDIENCE']
                : null,
          );
        }
        final configResult = await getIt<IAgentConfigRepository>()
            .getCurrentConfig();
        return configResult.fold(
          (config) {
            final base = config.serverUrl.trim();
            if (base.isEmpty) return null;
            final normalized = base.endsWith('/')
                ? base.substring(0, base.length - 1)
                : base;
            return JwksConfig(
              jwksUrl: '$normalized/.well-known/jwks.json',
              issuer: dotenv.env['JWKS_ISSUER']?.trim().isNotEmpty ?? false
                  ? dotenv.env['JWKS_ISSUER']
                  : null,
              audience: dotenv.env['JWKS_AUDIENCE']?.trim().isNotEmpty ?? false
                  ? dotenv.env['JWKS_AUDIENCE']
                  : null,
            );
          },
          (_) => null,
        );
      }),
    )
    ..registerLazySingleton<IClientTokenRepository>(
      () => ClientTokenRepository(getIt<ClientTokenLocalDataSource>()),
    )
    ..registerLazySingleton(
      () => ConnectionService(
        getIt<ITransportClient>(),
        getIt<IDatabaseGateway>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthService(getIt<IAuthClient>(), getIt<IAgentConfigRepository>()),
    )
    ..registerLazySingleton(
      () => QueryNormalizerService(getIt<QueryNormalizer>()),
    )
    ..registerLazySingleton(
      () => CompressionService(getIt<GzipCompressor>()),
    )
    ..registerLazySingleton(
      SqlOperationClassifier.new,
    )
    ..registerLazySingleton(
      () => ClientTokenValidationService(getIt<IAuthorizationPolicyResolver>()),
    )
    ..registerLazySingleton(() => ConfigService(getIt<ConfigValidator>()))
    ..registerLazySingleton(
      () => UpdateService(
        'https://api.example.com/updates', // This should be configurable
        DioFactory.createDio(),
      ),
    )
    ..registerLazySingleton(
      () => QueryProcessingService(
        getIt<ITransportClient>(),
        getIt<HandleQueryRequest>(),
      ),
    )
    ..registerLazySingleton(() => ConnectToHub(getIt<ConnectionService>()))
    ..registerLazySingleton(
      () => HandleQueryRequest(
        getIt<IDatabaseGateway>(),
        getIt<ITransportClient>(),
        getIt<QueryNormalizerService>(),
        getIt<CompressionService>(),
        getIt<AuthorizeSqlOperation>(),
        getIt<FeatureFlags>(),
        authMetrics: getIt<AuthorizationMetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => TestDbConnection(getIt<ConnectionService>()),
    )
    ..registerLazySingleton(
      () => CheckOdbcDriver(getIt<IOdbcDriverChecker>()),
    )
    ..registerLazySingleton(
      () => ExecutePlaygroundQuery(
        getIt<IDatabaseGateway>(),
        getIt<IAgentConfigRepository>(),
        getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton(
      () => ExecuteStreamingQuery(
        getIt<IStreamingDatabaseGateway>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentConfig(
        getIt<IAgentConfigRepository>(),
        getIt<ConfigService>(),
      ),
    )
    ..registerLazySingleton(
      () => LoadAgentConfig(getIt<IAgentConfigRepository>()),
    )
    ..registerLazySingleton(() => CheckForUpdates(getIt<UpdateService>()))
    ..registerLazySingleton(() => LoginUser(getIt<AuthService>()))
    ..registerLazySingleton(() => RefreshAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(() => SaveAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(
      () => CreateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ListClientTokens(getIt<IClientTokenRepository>()),
    )
    ..registerLazySingleton(
      () => RevokeClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthorizeSqlOperation(
        getIt<SqlOperationClassifier>(),
        getIt<ClientTokenValidationService>(),
      ),
    );

  // Conditional registrations based on capabilities
  if (capabilities.supportsTray) {
    developer.log('Registering TrayManagerService', name: 'service_locator');
    getIt.registerLazySingleton<ITrayService>(TrayManagerService.new);
  } else {
    developer.log(
      'Registering NoopTrayManagerService (degraded mode)',
      name: 'service_locator',
    );
    getIt.registerLazySingleton<ITrayService>(
      NoopTrayManagerService.new,
    );
  }

  if (capabilities.supportsWindowManager) {
    developer.log('Registering AutoStartService', name: 'service_locator');
    getIt.registerLazySingleton<IStartupService>(
      () => AutoStartService(prefs),
    );
  }

  if (capabilities.supportsNotifications) {
    developer.log(
      'Registering NotificationService',
      name: 'service_locator',
    );
    getIt.registerLazySingleton<INotificationService>(NotificationService.new);
  } else {
    developer.log(
      'Registering NoopNotificationService (degraded mode)',
      name: 'service_locator',
    );
    getIt.registerLazySingleton<INotificationService>(
      NoopNotificationService.new,
    );
  }

  // Register notification use cases (work with both real and noop services)
  getIt
    ..registerLazySingleton(
      () => SendNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => ScheduleNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => CancelNotification(getIt<INotificationService>()),
    )
    ..registerLazySingleton(
      () => CancelAllNotifications(getIt<INotificationService>()),
    );

  final odbcInitResult = await getIt<odbc.OdbcService>().initialize();
  odbcInitResult.fold(
    (_) {},
    (error) {
      throw StateError(
        'ODBC initialization failed during startup: $error',
      );
    },
  );

  // Initialize database
  final database = getIt<AppDatabase>();
  await database.customStatement('PRAGMA foreign_keys = ON');
}
