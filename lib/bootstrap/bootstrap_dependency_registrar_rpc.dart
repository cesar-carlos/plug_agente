part of 'bootstrap_dependency_registrar.dart';

void _registerRpc(
  GetIt getIt, {
  required int Function(String key, int fallback) readPositiveIntEnv,
  required int Function(String key, int fallback) readNonNegativeIntEnv,
}) {
  getIt
    ..registerLazySingleton(
      () => ActionIoRun(
        preparer: getIt<ActionIoIntentPreparer>(),
        admission: getIt<ActionIoAdmission>(),
        launcher: getIt<ActionIoSessionLauncher>(),
        supervisor: getIt<ActionIoSessionSupervisor>(),
        sessions: getIt<ActionIoJournalRuntime>().journal,
        authorization: getIt<ActionIoAuthorization>(),
      ),
    )
    ..registerLazySingleton(
      () => ActionIoValidateRun(
        getIt<ActionIoIntentPreparer>(),
        getIt<ActionIoAdmission>(),
      ),
    )
    ..registerLazySingleton(() {
      final runtime = getIt<ActionIoJournalRuntime>();
      return ActionIoRemoteAccess(
        installationId: getIt<AgentRuntimeIdentity>().runtimeInstanceId,
        authorization: getIt<ActionIoAuthorization>(),
        requestCancel: getIt<ActionIoSessionSupervisor>().requestCancel,
        metrics: getIt<MetricsCollector>().actionIoMetrics,
        input: runtime.journal,
        output: runtime.output,
        sessions: runtime.journal,
      );
    })
    ..registerLazySingleton<ISourceDiscoveryProbe>(
      () =>
          OdbcSourceDiscovery(getIt<odbc.OdbcService>(), getIt<ConfigService>(), getIt<DirectOdbcConnectionLimiter>()),
    )
    ..registerLazySingleton<ISqlOperationAuthorizer>(
      () => SqlOperationAuthorizer(getIt<ActiveConfigResolver>(), getIt<ClientTokenValidationService>()),
    )
    ..registerLazySingleton<ISqlOperationTransactionFactory>(
      () => OdbcSqlOperationTransactionFactory(
        getIt<odbc.OdbcService>(),
        getIt<ConfigService>(),
        getIt<DirectOdbcConnectionLimiter>(),
      ),
    )
    ..registerLazySingleton<SqlOperationExecutor>(
      () => SqlOperationExecutor(
        journal: getIt<ISqlOperationJournal>(),
        maintenanceGate: getIt<IUpdateMaintenanceGate>(),
        authorizer: getIt<ISqlOperationAuthorizer>(),
        transactions: getIt<ISqlOperationTransactionFactory>(),
        uuid: getIt<Uuid>(),
        onCleanupFailure: (operationId, failure) => developer.log(
          'SQL operation cleanup failed',
          name: 'sql_operations',
          level: 900,
          error: <String, Object>{'operationId': operationId},
        ),
      ),
    )
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
      () => DriftIdempotencyStore(getIt<AppDatabase>(), maintenanceGate: getIt<IUpdateMaintenanceGate>()),
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
        routeActionIoExecution: (legacy) => ActionIoExecutionRouter(
          legacy: legacy,
          ownsExecution: getIt<ActionIoJournalRuntime>().ownsExecution,
          faithful: ActionIoRpcHandler(
            legacy.method,
            accessProvider: () => getIt<ActionIoRemoteAccess>(),
            contract: ActionIoRpcContract(getIt<JsonSchemaContractValidator>()),
            enabled: () => getIt<FeatureFlags>().enableActionIo && getIt<ActionIoJournalRuntime>().isReady,
          ),
        ),
        actionIoRunHandler: ActionIoRpcHandler(
          'agent.action.run',
          contract: ActionIoRpcContract(getIt<JsonSchemaContractValidator>()),
          enabled: () => getIt<FeatureFlags>().enableActionIo && getIt<ActionIoJournalRuntime>().isReady,
          run: (request, context) => getIt<ActionIoRun>()(request, context),
        ),
        actionIoValidateHandler: ActionIoRpcHandler(
          'agent.action.validateRun',
          contract: ActionIoRpcContract(getIt<JsonSchemaContractValidator>()),
          enabled: () => getIt<FeatureFlags>().enableActionIo && getIt<ActionIoJournalRuntime>().isReady,
          validateRun: (request, context) => getIt<ActionIoValidateRun>()(request, context),
        ),
        additionalHandlers: [
          for (final method in ActionIoRpcHandler.methods)
            ActionIoRpcHandler(
              method,
              accessProvider: () => getIt<ActionIoRemoteAccess>(),
              contract: ActionIoRpcContract(getIt<JsonSchemaContractValidator>()),
              enabled: () => getIt<FeatureFlags>().enableActionIo && getIt<ActionIoJournalRuntime>().isReady,
            ),
          SourceSchemaRpcHandler(
            getIt<ActiveConfigResolver>(),
            getIt<ClientTokenValidationService>(),
            OdbcSourceSchema(
              OdbcSourceDiscovery(
                getIt<odbc.OdbcService>(),
                getIt<ConfigService>(),
                getIt<DirectOdbcConnectionLimiter>(),
              ),
            ),
          ),
          SourceDiscoveryRpcHandler(
            getIt<ActiveConfigResolver>(),
            getIt<ClientTokenValidationService>(),
            getIt<ISourceDiscoveryProbe>(),
          ),
          for (final method in ['sql.operation.execute', 'sql.operation.get', 'sql.operation.cancel'])
            SqlOperationRpcHandler(
              method,
              getIt<SqlOperationExecutor>(),
              enabled: () => getIt<FeatureFlags>().enableSqlOperations,
            ),
        ],
      ),
    )
    ..registerLazySingleton<IRpcRequestDispatcher>(
      getIt.get<RpcMethodDispatcher>,
    );
}
