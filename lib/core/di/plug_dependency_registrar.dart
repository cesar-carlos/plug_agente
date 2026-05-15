import 'dart:developer' as developer;

import 'package:get_it/get_it.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/application/gateway/queued_database_gateway.dart';
import 'package:plug_agente/application/queue/sql_execution_queue.dart';
import 'package:plug_agente/application/rpc/client_token_get_policy_rate_limiter.dart';
import 'package:plug_agente/application/rpc/rpc_method_dispatcher.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/services/auth_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/services/connection_service.dart';
import 'package:plug_agente/application/services/health_service.dart';
import 'package:plug_agente/application/services/hub_recovery_auth_coordinator.dart';
import 'package:plug_agente/application/services/protocol_negotiator.dart';
import 'package:plug_agente/application/services/query_normalizer_service.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_hub_availability.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/application/use_cases/get_client_token_secret.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
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
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/runtime/odbc_runtime_tuning.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/noop_tray_manager_service.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_hub_profile_gateway.dart';
import 'package:plug_agente/domain/repositories/i_auth_client.dart';
import 'package:plug_agente/domain/repositories/i_authorization_cache_metrics.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_authorization_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_connected_agents_gateway.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_hub_auth_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_hub_availability_probe.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/domain/repositories/i_local_app_data_backup_service.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';
import 'package:plug_agente/domain/repositories/i_odbc_driver_checker.dart';
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';
import 'package:plug_agente/domain/repositories/i_rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/domain/repositories/i_sql_investigation_collector.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/domain/repositories/i_transport_client.dart';
import 'package:plug_agente/infrastructure/backup/local_app_data_backup_service.dart';
import 'package:plug_agente/infrastructure/cache/client_token_policy_memory_cache.dart';
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/datasources/socket_data_source.dart';
import 'package:plug_agente/infrastructure/external_services/agent_hub_profile_rest_client.dart';
import 'package:plug_agente/infrastructure/external_services/auth_client.dart';
import 'package:plug_agente/infrastructure/external_services/connected_agents_rest_client.dart';
import 'package:plug_agente/infrastructure/external_services/dio_factory.dart';
import 'package:plug_agente/infrastructure/external_services/hub_availability_probe.dart';
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
import 'package:plug_agente/infrastructure/metrics/odbc_native_metrics_service.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/metrics/rpc_dispatch_metrics_collector.dart';
import 'package:plug_agente/infrastructure/metrics/sql_investigation_collector.dart';
import 'package:plug_agente/infrastructure/pool/direct_odbc_connection_limiter.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool_factory.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_repository.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';
import 'package:plug_agente/infrastructure/retry/retry_manager.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';
import 'package:plug_agente/infrastructure/services/authorization_policy_resolver.dart';
import 'package:plug_agente/infrastructure/services/auto_start_service.dart';
import 'package:plug_agente/infrastructure/services/http_silent_update_installer.dart';
import 'package:plug_agente/infrastructure/services/noop_notification_service.dart';
import 'package:plug_agente/infrastructure/services/notification_service.dart';
import 'package:plug_agente/infrastructure/stores/file_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/flutter_secure_token_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_idempotency_store.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_revoked_token_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_hub_auth_secret_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_audit_store.dart';
import 'package:plug_agente/infrastructure/stores/noop_token_secret_store.dart';
import 'package:uuid/uuid.dart';

/// Registers transport, ODBC, auth, and application use-case graph on [getIt].
void registerPlugDependencyGraph(
  GetIt getIt, {
  required odbc.ServiceLocator odbcWorkerLocator,
}) {
  int readPositiveIntEnv(String key, int fallback) {
    final raw = AppEnvironment.get(key);
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) {
      return fallback;
    }
    return parsed;
  }

  int readNonNegativeIntEnv(String key, int fallback) {
    final raw = AppEnvironment.get(key);
    if (raw == null || raw.isEmpty) {
      return fallback;
    }
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0) {
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
    ..registerLazySingleton<IHubAuthSecretStore>(
      () {
        try {
          return FlutterSecureHubAuthSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureHubAuthSecretStore init failed, using NoopHubAuthSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopHubAuthSecretStore();
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
      () => AgentConfigRepository(
        getIt<AppDatabase>(),
        authSecretStore: getIt<IHubAuthSecretStore>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentRegisterProfileProvider(
        configRepository: getIt<IAgentConfigRepository>(),
      ),
    )
    ..registerLazySingleton(() => const Uuid())
    ..registerLazySingleton<IConnectionPool>(
      () => createOdbcConnectionPool(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
        getIt<MetricsCollector>(),
        getIt<FeatureFlags>(),
        getIt<IAgentConfigRepository>(),
      ),
    )
    ..registerLazySingleton<IRetryManager>(RetryManager.new)
    ..registerLazySingleton<SqlInvestigationCollector>(SqlInvestigationCollector.new)
    ..registerLazySingleton<ISqlInvestigationCollector>(getIt.get<SqlInvestigationCollector>)
    ..registerLazySingleton(MetricsCollector.new)
    ..registerLazySingleton(
      () => HealthService(
        metricsCollector: getIt<MetricsCollector>(),
        gateway: getIt<IDatabaseGateway>(),
        odbcSettings: getIt<IOdbcConnectionSettings>(),
        connectionPool: getIt<IConnectionPool>(),
        configRepository: getIt<IAgentConfigRepository>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        featureFlags: getIt<FeatureFlags>(),
        odbcRuntimeTuning: getIt<OdbcRuntimeTuning>(),
      ),
    )
    ..registerLazySingleton(
      () => DirectOdbcConnectionLimiter(
        maxConcurrent: ConnectionConstants.directOdbcConnectionConcurrency(
          getIt<IOdbcConnectionSettings>().poolSize,
        ),
        acquireTimeout: ConnectionConstants.defaultPoolAcquireTimeout,
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => OdbcNativeMetricsService(
        getIt<odbc.OdbcService>(),
        configRepository: getIt<IAgentConfigRepository>(),
        connectionPool: getIt<IConnectionPool>(),
        settings: getIt<IOdbcConnectionSettings>(),
        runtimeTuning: getIt<OdbcRuntimeTuning>(),
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton<IMetricsCollector>(getIt.get<MetricsCollector>)
    ..registerLazySingleton<IRpcDispatchMetricsCollector>(
      () => RpcDispatchMetricsCollector(getIt<MetricsCollector>()),
    )
    ..registerLazySingleton(
      () => ClientTokenGetPolicyRateLimiter(
        maxCallsPerMinute: readNonNegativeIntEnv(
          'CLIENT_TOKEN_GET_POLICY_MAX_PER_MINUTE',
          ConnectionConstants.clientTokenGetPolicyDefaultMaxPerMinute,
        ),
        maxScopeEntries: readNonNegativeIntEnv(
          'CLIENT_TOKEN_GET_POLICY_MAX_SCOPE_KEYS',
          ConnectionConstants.clientTokenGetPolicyDefaultMaxScopeKeys,
        ),
      ),
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
        healthService: getIt<HealthService>(),
        normalizerService: getIt<QueryNormalizerService>(),
        uuid: getIt<Uuid>(),
        authorizeSqlOperation: getIt<AuthorizeSqlOperation>(),
        getClientTokenPolicy: getIt<GetClientTokenPolicy>(),
        getPolicyRateLimiter: getIt<ClientTokenGetPolicyRateLimiter>(),
        featureFlags: getIt<FeatureFlags>(),
        configRepository: getIt<IAgentConfigRepository>(),
        idempotencyStore: getIt<IIdempotencyStore>(),
        authMetrics: getIt<IAuthorizationMetricsCollector>(),
        deprecationMetrics: getIt<IDeprecationMetricsCollector>(),
        dispatchMetrics: getIt<IRpcDispatchMetricsCollector>(),
        onIdempotencyFingerprintMismatch: getIt<MetricsCollector>().recordIdempotencyFingerprintMismatch,
        sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
        odbcNativeMetricsService: getIt<OdbcNativeMetricsService>(),
      ),
    )
    ..registerLazySingleton<ITransportClient>(
      () {
        PayloadSigningConfig environmentSigningConfig() {
          final signingKey = AppEnvironment.get('PAYLOAD_SIGNING_KEY');
          final signingKeyId = AppEnvironment.get('PAYLOAD_SIGNING_KEY_ID');
          return PayloadSigningConfig(
            activeKeyId: signingKeyId,
            keys: {
              if (signingKeyId != null && signingKey != null) signingKeyId: signingKey,
            },
            source: PayloadSigningConfigSource.environment,
          );
        }

        final signingConfig = getIt.isRegistered<PayloadSigningConfig>()
            ? getIt<PayloadSigningConfig>()
            : environmentSigningConfig();
        PayloadSigner? payloadSigner;
        if (signingConfig.hasConfiguredSigner) {
          payloadSigner = PayloadSigner(
            keys: signingConfig.keys,
            activeKeyId: signingConfig.activeKeyId,
          );
          developer.log(
            'PayloadFrame signer configured '
            '(active_key_id=${payloadSigner.activeKeyId}, key_count=${payloadSigner.keyCount}, '
            'source=${signingConfig.sourceName})',
            name: 'plug_dependency_registrar',
            level: 800,
          );
        }
        for (final warning in signingConfig.warnings) {
          developer.log(
            'PayloadFrame signing configuration warning: $warning',
            name: 'plug_dependency_registrar',
            level: 900,
          );
        }
        return SocketIOTransportClientV2(
          dataSource: getIt<SocketDataSource>(),
          negotiator: getIt<ProtocolNegotiator>(),
          rpcDispatcher: getIt<RpcMethodDispatcher>(),
          featureFlags: getIt<FeatureFlags>(),
          payloadSigner: payloadSigner,
          payloadSigningConfig: signingConfig,
          protocolMetricsCollector: getIt<ProtocolMetricsCollector>(),
          registerProfileProvider: getIt<AgentRegisterProfileProvider>().loadSnapshot,
        );
      },
    )
    ..registerLazySingleton<IDatabaseGateway>(
      () {
        // Create base ODBC gateway
        final baseGateway = OdbcDatabaseGateway(
          getIt<IAgentConfigRepository>(),
          getIt<odbc.OdbcService>(),
          getIt<IConnectionPool>(),
          getIt<IRetryManager>(),
          getIt<MetricsCollector>(),
          getIt<IOdbcConnectionSettings>(),
          featureFlags: getIt<FeatureFlags>(),
          directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
          sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        );

        // Wrap with SQL execution queue for backpressure control
        final sqlQueueMaxWorkers = ConnectionConstants.sqlQueueMaxWorkersForPoolSize(
          getIt<IOdbcConnectionSettings>().poolSize,
        );
        final persistedPoolSize = getIt<IOdbcConnectionSettings>().poolSize;
        if (sqlQueueMaxWorkers == persistedPoolSize) {
          getIt<MetricsCollector>().recordSqlQueueWorkersEqualPool(
            workers: sqlQueueMaxWorkers,
            poolSize: persistedPoolSize,
          );
        }
        final sqlQueue = SqlExecutionQueue(
          maxQueueSize: ConnectionConstants.sqlQueueMaxSize,
          maxConcurrentWorkers: sqlQueueMaxWorkers,
          metricsCollector: getIt<MetricsCollector>(),
          defaultEnqueueTimeout: ConnectionConstants.sqlQueueEnqueueTimeout,
        );

        developer.log(
          'SQL queue initialized: maxSize=${ConnectionConstants.sqlQueueMaxSize}, '
          'maxWorkers=$sqlQueueMaxWorkers',
          name: 'plug_dependency_registrar',
          level: 800,
        );

        return QueuedDatabaseGateway(
          delegate: baseGateway,
          queue: sqlQueue,
        );
      },
    )
    ..registerLazySingleton<IStreamingDatabaseGateway>(
      () => OdbcStreamingGateway(
        getIt<odbc.OdbcService>(),
        getIt<IOdbcConnectionSettings>(),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        metricsCollector: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton<IOdbcDriverChecker>(OdbcDriverChecker.new)
    ..registerLazySingleton<IAuthClient>(
      () => AuthClient(DioFactory.createDio()),
    )
    ..registerLazySingleton<IConnectedAgentsGateway>(
      () => ConnectedAgentsRestClient(
        DioFactory.createDio(
          requestTimeout: ConnectionConstants.backupRestoreAgentsListTimeout,
        ),
      ),
    )
    ..registerLazySingleton<ILocalAppDataBackupService>(
      () => LocalAppDataBackupService(
        database: getIt<AppDatabase>(),
        storageContext: getIt<GlobalStorageContext>(),
        settingsStore: getIt<IAppSettingsStore>(),
        authClient: getIt<IAuthClient>(),
        connectedAgentsGateway: getIt<IConnectedAgentsGateway>(),
      ),
    )
    ..registerLazySingleton<IHubAvailabilityProbe>(
      () {
        final probePath = AppEnvironment.get('HUB_AVAILABILITY_PROBE_PATH');
        return HubAvailabilityProbe(
          probePath: (probePath != null && probePath.isNotEmpty)
              ? probePath
              : AppConstants.defaultHubAvailabilityProbePath,
        );
      },
    )
    ..registerLazySingleton<IAgentHubProfileGateway>(
      () => AgentHubProfileRestClient(DioFactory.createDio()),
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
    ..registerLazySingleton(
      () => GetClientTokenPolicy(getIt<IAuthorizationPolicyResolver>()),
    )
    ..registerLazySingleton<JwtJwksVerifier>(
      () => JwtJwksVerifier(() async {
        final jwksUrlOverride = AppEnvironment.get('JWKS_URL');
        if (jwksUrlOverride != null && jwksUrlOverride.isNotEmpty) {
          return JwksConfig(
            jwksUrl: jwksUrlOverride,
            issuer: AppEnvironment.get('JWKS_ISSUER'),
            audience: AppEnvironment.get('JWKS_AUDIENCE'),
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
              issuer: AppEnvironment.get('JWKS_ISSUER'),
              audience: AppEnvironment.get('JWKS_AUDIENCE'),
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
      ),
    )
    ..registerLazySingleton(
      () => AuthService(getIt<IAuthClient>(), getIt<IAgentConfigRepository>()),
    )
    ..registerLazySingleton(
      () => HubRecoveryAuthCoordinator(
        getIt<LoadAgentConfig>(),
        getIt<LoginUser>(),
        getIt<RefreshAuthToken>(),
        getIt<SaveAuthToken>(),
        getIt<IAgentConfigRepository>(),
      ),
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
      () => CheckHubAvailability(getIt<IHubAvailabilityProbe>()),
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
    ..registerLazySingleton<ISilentUpdateInstaller>(
      HttpSilentUpdateInstaller.new,
    )
    ..registerLazySingleton<IAutoUpdateOrchestrator>(
      () => AutoUpdateOrchestrator(
        getIt<RuntimeCapabilities>(),
        silentUpdateInstaller: getIt<ISilentUpdateInstaller>(),
        settingsStore: getIt<IAppSettingsStore>(),
        metricsCollector: getIt<MetricsCollector>(),
        closeApplicationForSilentUpdate: () async {
          if (getIt.isRegistered<WindowManagerService>()) {
            await getIt<WindowManagerService>().close();
          }
        },
      ),
    )
    ..registerLazySingleton(
      () => PushAgentProfileToHub(
        getIt<IAgentHubProfileGateway>(),
        getIt<Uuid>(),
      ),
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
      () => GetClientTokenSecret(getIt<IClientTokenRepository>()),
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
