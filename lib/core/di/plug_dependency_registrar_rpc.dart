part of 'plug_dependency_registrar.dart';

void _registerRpc(
  GetIt getIt, {
  required int Function(String key, int fallback) readPositiveIntEnv,
  required int Function(String key, int fallback) readNonNegativeIntEnv,
}) {
  getIt
    ..registerLazySingleton<SqlRpcMethodHandlerOperationsFactory>(
      () => SqlRpcMethodHandlerOperationsFactory(
        getIt<IStreamingNamedParameterPreparer>(),
      ),
    )
    ..registerLazySingleton<AgentActionRpcMethodHandlerOperationsFactory>(
      () => const AgentActionRpcMethodHandlerOperationsFactory(),
    )
    ..registerLazySingleton<AgentMetadataRpcMethodHandlerOperationsFactory>(
      () => const AgentMetadataRpcMethodHandlerOperationsFactory(),
    )
    ..registerLazySingleton(
      () => DefaultRpcMethodHandlerOperationsFactory(
        sqlFactory: getIt<SqlRpcMethodHandlerOperationsFactory>(),
        agentActionFactory: getIt<AgentActionRpcMethodHandlerOperationsFactory>(),
        metadataFactory: getIt<AgentMetadataRpcMethodHandlerOperationsFactory>(),
      ),
    )
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
    ..registerLazySingleton(
      () => AgentActionRemoteRateLimiter(
        maxCallsPerMinute: readNonNegativeIntEnv(
          'AGENT_ACTION_REMOTE_MAX_PER_MINUTE',
          0,
        ),
        maxScopeEntries: readNonNegativeIntEnv(
          'AGENT_ACTION_REMOTE_MAX_SCOPE_KEYS',
          8192,
        ),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteLifecycleAuditRecorder(
        featureFlags: getIt<FeatureFlags>(),
        auditStore: getIt<IAgentActionRemoteAuditStore>(),
        runtimeIdentity: getIt<AgentRuntimeIdentity>(),
        uuid: getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton<IAuthorizationCacheMetrics>(
      () => AuthorizationCacheMetricsCollector(getIt<MetricsCollector>()),
    )
    ..registerLazySingleton<IIdempotencyStore>(
      () => DriftIdempotencyStore(getIt<AppDatabase>()),
    )
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
    ..registerLazySingleton<IAgentActionRemoteAuditStore>(
      () => AgentActionRemoteAuditDriftStore(getIt<AppDatabase>()),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteAuthorizationService(
        featureFlags: getIt<FeatureFlags>(),
        getClientTokenPolicy: getIt<GetClientTokenPolicy>(),
        authorizeSqlOperation: getIt<AuthorizeSqlOperation>(),
        authorizationStageBudget: const Duration(seconds: 3),
        onPermissionDenied: getIt<MetricsCollector>().recordRemotePermissionDenied,
      ),
    )
    ..registerLazySingleton(OpenRpcDocumentLoader.new)
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
        activeConfigResolver: getIt<ActiveConfigResolver>(),
        configQueryCache: getIt<IActiveConfigQueryCache>(),
        streamingConnectionStringCache: getIt<SqlStreamingConnectionStringCache>(),
        idempotencyStore: getIt<IIdempotencyStore>(),
        authMetrics: getIt<IAuthorizationMetricsCollector>(),
        deprecationMetrics: getIt<IDeprecationMetricsCollector>(),
        dispatchMetrics: getIt<IRpcDispatchMetricsCollector>(),
        onIdempotencyFingerprintMismatch: getIt<MetricsCollector>().recordIdempotencyFingerprintMismatch,
        onAgentActionRemoteAuditExecutionCorrelated: getIt<MetricsCollector>().recordRemoteAuditExecutionCorrelated,
        onAgentActionRemoteRateLimited: getIt<MetricsCollector>().recordRemoteRateLimited,
        sqlInvestigation: getIt<ISqlInvestigationCollector>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
        odbcNativeMetricsService: getIt<OdbcNativeMetricsService>(),
        runAgentActionLocally: getIt<RunAgentActionLocally>(),
        runAgentActionViaRemoteTrigger: getIt<RunAgentActionViaRemoteTrigger>(),
        cancelAgentActionExecution: getIt<CancelAgentActionExecution>(),
        getAgentActionExecution: getIt<GetAgentActionExecution>(),
        sliceAgentActionCapturedOutput: getIt<SliceAgentActionCapturedOutput>(),
        getAgentActionDefinition: getIt<GetAgentActionDefinition>(),
        backfillAgentActionExecutionCorrelation: getIt<BackfillAgentActionExecutionCorrelation>(),
        agentActionRemoteRateLimiter: getIt<AgentActionRemoteRateLimiter>(),
        agentActionRemoteAuthorization: getIt<AgentActionRemoteAuthorizationService>(),
        agentActionRemoteAuditStore: getIt<IAgentActionRemoteAuditStore>(),
        agentActionRuntimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        agentRuntimeIdentity: getIt<AgentRuntimeIdentity>(),
        agentActionRetentionSettings: getIt<AgentActionRetentionSettings>(),
        loadOpenRpcDocument: getIt<OpenRpcDocumentLoader>().getDocument,
        odbcConnectionSettings: getIt<IOdbcConnectionSettings>(),
        inFlightAbortPort: getIt<ISqlInFlightExecutionAbortPort>(),
        operationsFactory: getIt<DefaultRpcMethodHandlerOperationsFactory>(),
      ),
    )
    ..registerLazySingleton<IRpcRequestDispatcher>(
      getIt.get<RpcMethodDispatcher>,
    );
}
