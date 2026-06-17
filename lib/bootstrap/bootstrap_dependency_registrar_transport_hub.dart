part of 'bootstrap_dependency_registrar.dart';

void _registerTransportHub(GetIt getIt) {
  getIt
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
          negotiator: getIt<IProtocolNegotiator>(),
          rpcDispatcher: getIt<IRpcRequestDispatcher>(),
          featureFlags: getIt<FeatureFlags>(),
          options: SocketIOTransportClientV2Options(
            payloadSigner: payloadSigner,
            payloadSigningConfig: signingConfig,
            protocolMetricsCollector: getIt<ProtocolMetricsCollector>(),
            metricsCollector: getIt<MetricsCollector>(),
            agentActionsRemoteCapabilityProvider: getIt<IAgentActionsRemoteCapabilityProvider>(),
            agentActionLocalRunnerRegistry: getIt<AgentActionLocalRunnerRegistry>(),
            registerProfileProvider: getIt<AgentRegisterProfileProvider>().loadSnapshot,
            jsonSchemaValidator: getIt.isRegistered<JsonSchemaContractValidator>()
                ? getIt<JsonSchemaContractValidator>()
                : null,
          ),
        );
      },
    )
    ..registerLazySingleton<IAuthClient>(
      () => AuthClient(DioFactory.createDio()),
    )
    ..registerLazySingleton<IConnectedAgentsGateway>(
      () => ConnectedAgentsRestClient(
        DioFactory.createDio(
          requestTimeout: ConnectionConstants.backupRestoreAgentsListTimeout,
        ),
        accessTokenRenewer: getIt<HubAccessTokenRenewer>(),
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
    ..registerLazySingleton(HubAccessTokenRefreshGate.new)
    ..registerLazySingleton(
      () => HubAccessTokenRenewer(
        getIt<HubSessionCoordinator>(),
        getIt<HubAccessTokenRefreshGate>(),
      ),
    )
    ..registerLazySingleton<IAgentHubProfileGateway>(
      () => AgentHubProfileRestClient(
        DioFactory.createDio(
          requestTimeout: ConnectionConstants.agentHubProfileHttpTimeout,
        ),
        accessTokenRenewer: getIt<HubAccessTokenRenewer>(),
      ),
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
    ..registerLazySingleton<IOpenCnpjLookup>(() => getIt<OpenCnpjClient>())
    ..registerLazySingleton<IViaCepLookup>(() => getIt<ViaCepClient>())
    ..registerLazySingleton(() => LookupAgentCnpj(getIt<IOpenCnpjLookup>()))
    ..registerLazySingleton(() => LookupAgentCep(getIt<IViaCepLookup>()))
    ..registerLazySingleton<IAuthorizationPolicyResolver>(
      () => AuthorizationPolicyResolver(
        getIt<FeatureFlags>(),
        jwksVerifier: getIt<JwtJwksVerifier>(),
        clientTokenRepository: getIt<IClientTokenRepository>(),
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
        final configResult = await getIt<ActiveConfigResolver>().resolveActiveOrFallback(
          metadataOnly: true,
        );
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
      () => ClientTokenRepository(
        getIt<ClientTokenLocalDataSource>(),
        secretStore: getIt<ITokenSecretStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ConnectionService(
        getIt.call<ITransportClient>,
        getIt<IDatabaseGateway>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthService(getIt<IAuthClient>(), getIt<IHubSessionStore>()),
    )
    ..registerLazySingleton(
      () => HubSessionCoordinator(
        getIt<ActiveConfigResolver>(),
        getIt<LoginUser>(),
        getIt<RefreshAuthToken>(),
        getIt<SaveAuthToken>(),
        getIt<IHubSessionStore>(),
      ),
    );
}
