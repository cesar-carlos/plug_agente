import 'dart:developer' as developer;

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
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
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/application/validation/config_validator.dart';
import 'package:plug_agente/application/validation/query_normalizer.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/noop_tray_manager_service.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';
import 'package:plug_agente/infrastructure/external_services/jwt_jwks_verifier.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_database_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_driver_checker.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_streaming_gateway.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/socket_io_transport_client_v2.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_cache_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/authorization_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/deprecation_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool_factory.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/noop_notification_service.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:plug_agente/infrastructure/stores/file_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_token_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_secret_store.dart';
import 'package:uuid/uuid.dart';

/// Registers transport, ODBC, auth, and application use-case graph on [getIt].
void registerPlugDependencyGraph(
  GetIt getIt, {
  required odbc.ServiceLocator odbcWorkerLocator,
}) {
  int readPositiveIntEnv(String key, int fallback) {
    final raw = dotenv.env[key]?.trim();
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) {
      return fallback;
    }
    return parsed;
  }

  getIt
    ..registerLazySingleton<odbc.OdbcService>(
      () => odbcWorkerLocator.asyncService,
    )
    ..registerLazySingleton(ConfigValidator.new)
    ..registerLazySingleton(QueryNormalizer.new)
    ..registerLazySingleton(SocketDataSource.new)
    ..registerLazySingleton(
      () => AppDatabase(
        databaseFilePath: getIt<GlobalStorageContext>().databaseFilePath,
      ),
    )
    ..registerLazySingleton<ITokenSecretStore>(
      () {
        try {
          return FlutterSecureTokenSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureTokenSecretStore init failed, using NoopTokenSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopTokenSecretStore();
        }
      },
    )
    ..registerLazySingleton(
      () => ClientTokenLocalDataSource(
        getIt<AppDatabase>(),
        secretStore: getIt<ITokenSecretStore>(),
      ),
    )
    ..registerLazySingleton(ProtocolNegotiator.new)
    ..registerLazySingleton(ProtocolMetricsCollector.new)
    ..registerLazySingleton(AuthorizationMetricsCollector.new)
    ..registerLazySingleton<IAuthorizationMetricsCollector>(
      getIt.get<AuthorizationMetricsCollector>,
    )
    ..registerLazySingleton(DeprecationMetricsCollector.new)
    ..registerLazySingleton<IDeprecationMetricsCollector>(
      getIt.get<DeprecationMetricsCollector>,
    )
    ..registerLazySingleton<IAgentConfigRepository>(
      () => AgentConfigRepository(getIt<AppDatabase>()),
    )
    ..registerLazySingleton(() => const Uuid())
    ..registerLazySingleton<IConnectionPool>(
      () => createOdbcConnectionPool(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    )
    ..registerLazySingleton<IRetryManager>(RetryManager.new)
    ..registerLazySingleton(MetricsCollector.new)
    ..registerLazySingleton<IMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton<IRpcDispatchMetricsCollector>(
      () => RpcDispatchMetricsCollector(getIt<MetricsCollector>()),
    )
    ..registerLazySingleton<IAuthorizationCacheMetrics>(
      () => AuthorizationCacheMetricsCollector(getIt<MetricsCollector>()),
    )
    ..registerLazySingleton<IIdempotencyStore>(InMemoryIdempotencyStore.new)
    ..registerLazySingleton<IAuthorizationDecisionCache>(
      () => InMemoryAuthorizationDecisionCache(
        maxEntries: readPositiveIntEnv(
          'AUTH_DECISION_CACHE_MAX_ENTRIES',
          8192,
        ),
      ),
    )
    ..registerLazySingleton<IClientTokenPolicyCache>(
      () => ClientTokenPolicyMemoryCache(
        maxEntries: readPositiveIntEnv(
          'AUTH_POLICY_CACHE_MAX_ENTRIES',
          2048,
        ),
      ),
    )
    ..registerLazySingleton<IRevokedTokenStore>(InMemoryRevokedTokenStore.new)
    ..registerLazySingleton<ITokenAuditStore>(
      () => getIt<FeatureFlags>().enableTokenAudit ? FileTokenAuditStore() : NoopTokenAuditStore(),
    )
    ..registerLazySingleton(
      () => RpcMethodDispatcher(
        databaseGateway: getIt<IDatabaseGateway>(),
        normalizerService: getIt<QueryNormalizerService>(),
        uuid: getIt<Uuid>(),
        authorizeSqlOperation: getIt<AuthorizeSqlOperation>(),
        featureFlags: getIt<FeatureFlags>(),
        configRepository: getIt<IAgentConfigRepository>(),
        idempotencyStore: getIt<IIdempotencyStore>(),
        authMetrics: getIt<IAuthorizationMetricsCollector>(),
        deprecationMetrics: getIt<IDeprecationMetricsCollector>(),
        dispatchMetrics: getIt<IRpcDispatchMetricsCollector>(),
        onIdempotencyFingerprintMismatch: getIt<MetricsCollector>().recordIdempotencyFingerprintMismatch,
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
      ),
    )
    ..registerLazySingleton<ITransportClient>(
      () {
        final signingKey = dotenv.env['PAYLOAD_SIGNING_KEY']?.trim();
        final signingKeyId = dotenv.env['PAYLOAD_SIGNING_KEY_ID']?.trim();
        PayloadSigner? payloadSigner;
        if (signingKey != null && signingKey.isNotEmpty && signingKeyId != null && signingKeyId.isNotEmpty) {
          payloadSigner = PayloadSigner(keys: {signingKeyId: signingKey});
        }
        return SocketIOTransportClientV2(
          dataSource: getIt<SocketDataSource>(),
          negotiator: getIt<ProtocolNegotiator>(),
          rpcDispatcher: getIt<RpcMethodDispatcher>(),
          featureFlags: getIt<FeatureFlags>(),
          payloadSigner: payloadSigner,
        );
      },
    )
    ..registerLazySingleton<IDatabaseGateway>(
      () => OdbcDatabaseGateway(
        getIt<IAgentConfigRepository>(),
        getIt<odbc.OdbcService>(),
        getIt<IConnectionPool>(),
        getIt<IRetryManager>(),
        getIt<MetricsCollector>(),
        getIt<IOdbcConnectionSettings>(),
        featureFlags: getIt<FeatureFlags>(),
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
    ..registerLazySingleton(
      () => ViaCepClient(
        DioFactory.createDio(
          requestTimeout: const Duration(
            seconds: AppConstants.publicApiTimeoutSeconds,
          ),
        ),
      ),
    )
    ..registerLazySingleton(
      () => OpenCnpjClient(
        DioFactory.createDio(
          requestTimeout: const Duration(
            seconds: AppConstants.publicApiTimeoutSeconds,
          ),
        ),
      ),
    )
    ..registerLazySingleton<IAuthorizationPolicyResolver>(
      () => AuthorizationPolicyResolver(
        getIt<FeatureFlags>(),
        jwksVerifier: getIt<JwtJwksVerifier>(),
        localDataSource: getIt<ClientTokenLocalDataSource>(),
        revokedTokenStore: getIt<IRevokedTokenStore>(),
        tokenAuditStore: getIt<ITokenAuditStore>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
        cacheMetrics: getIt<IAuthorizationCacheMetrics>(),
      ),
    )
    ..registerLazySingleton<JwtJwksVerifier>(
      () => JwtJwksVerifier(() async {
        final jwksUrlOverride = dotenv.env['JWKS_URL']?.trim();
        if (jwksUrlOverride != null && jwksUrlOverride.isNotEmpty) {
          return JwksConfig(
            jwksUrl: jwksUrlOverride,
            issuer: dotenv.env['JWKS_ISSUER']?.trim().isNotEmpty ?? false ? dotenv.env['JWKS_ISSUER'] : null,
            audience: dotenv.env['JWKS_AUDIENCE']?.trim().isNotEmpty ?? false ? dotenv.env['JWKS_AUDIENCE'] : null,
          );
        }
        final configResult = await getIt<IAgentConfigRepository>().getCurrentConfig();
        return configResult.fold(
          (config) {
            final base = config.serverUrl.trim();
            if (base.isEmpty) return null;
            final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
            return JwksConfig(
              jwksUrl: '$normalized/.well-known/jwks.json',
              issuer: dotenv.env['JWKS_ISSUER']?.trim().isNotEmpty ?? false ? dotenv.env['JWKS_ISSUER'] : null,
              audience: dotenv.env['JWKS_AUDIENCE']?.trim().isNotEmpty ?? false ? dotenv.env['JWKS_AUDIENCE'] : null,
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
        getIt.call<ITransportClient>,
        getIt<IDatabaseGateway>(),
        getIt<IRetryManager>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthService(getIt<IAuthClient>(), getIt<IAgentConfigRepository>()),
    )
    ..registerLazySingleton(
      () => QueryNormalizerService(getIt<QueryNormalizer>()),
    )
    ..registerLazySingleton(
      SqlOperationClassifier.new,
    )
    ..registerLazySingleton(
      () => ClientTokenValidationService(getIt<IAuthorizationPolicyResolver>()),
    )
    ..registerLazySingleton(() => ConfigService(getIt<ConfigValidator>()))
    ..registerLazySingleton(() => ConnectToHub(getIt<ConnectionService>()))
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
    ..registerLazySingleton<IAutoUpdateOrchestrator>(
      () => AutoUpdateOrchestrator(getIt<RuntimeCapabilities>()),
    )
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
      () => UpdateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => RevokeClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthorizeSqlOperation(
        getIt<SqlOperationClassifier>(),
        getIt<ClientTokenValidationService>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        cacheMetrics: getIt<IAuthorizationCacheMetrics>(),
      ),
    );
}

/// Tray, startup, notification services and notification use cases.
void registerPlugCapabilityServices(
  GetIt getIt,
  RuntimeCapabilities capabilities,
) {
  if (capabilities.supportsTray) {
    developer.log(
      'Registering TrayManagerService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<ITrayService>(TrayManagerService.new);
  } else {
    developer.log(
      'Registering NoopTrayManagerService (degraded mode)',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<ITrayService>(
      NoopTrayManagerService.new,
    );
  }

  if (capabilities.supportsWindowManager) {
    developer.log(
      'Registering AutoStartService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<IStartupService>(
      AutoStartService.new,
    );
  }

  if (capabilities.supportsNotifications) {
    developer.log(
      'Registering NotificationService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<INotificationService>(NotificationService.new);
  } else {
    developer.log(
      'Registering NoopNotificationService (degraded mode)',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<INotificationService>(
      NoopNotificationService.new,
    );
  }

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
}
