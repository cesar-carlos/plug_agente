part of 'plug_dependency_registrar.dart';

void _registerHealth(GetIt getIt) {
  getIt
    ..registerLazySingleton(SecureStorageRuntimeProbe.new)
    ..registerLazySingleton<AgentActionRetentionSettings>(
      () => AgentActionRetentionSettings(getIt<IAppSettingsStore>()),
    )
    ..registerLazySingleton<AgentActionPreflightSettings>(
      () => AgentActionPreflightSettings(getIt<IAppSettingsStore>()),
    )
    ..registerLazySingleton(
      () => HealthService(
        metricsCollector: getIt<MetricsCollector>(),
        gateway: getIt<IDatabaseGateway>(),
        odbcSettings: getIt<IOdbcConnectionSettings>(),
        connectionPool: getIt<IConnectionPool>(),
        activeConfigResolver: getIt<ActiveConfigResolver>(),
        streamingGateway: getIt<IStreamingDatabaseGateway>(),
        directConnectionLimiter: getIt<DirectOdbcConnectionLimiter>(),
        poolDiscardDiagnostics: _resolvePoolDiscardInflightDiagnostics(getIt<IDatabaseGateway>()),
        featureFlags: getIt<FeatureFlags>(),
        odbcRuntimeTuning: getIt<OdbcRuntimeTuning>(),
        agentRuntimeIdentity: getIt<AgentRuntimeIdentity>(),
        agentActionRunnerRegistry: getIt<AgentActionLocalRunnerRegistry>(),
        agentActionRuntimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
        agentActionRetentionSettings: getIt<AgentActionRetentionSettings>(),
        agentActionTriggerScheduler: getIt.isRegistered<AgentActionTriggerScheduler>()
            ? getIt<AgentActionTriggerScheduler>()
            : null,
        agentActionSchedulerInstanceLock: getIt.isRegistered<IAgentActionSchedulerInstanceLock>()
            ? getIt<IAgentActionSchedulerInstanceLock>()
            : null,
        globalStorageHealthSnapshotBuilder: getIt.isRegistered<IGlobalStorageHealthSnapshotBuilder>()
            ? getIt<IGlobalStorageHealthSnapshotBuilder>()
            : null,
        globalStorageContext: getIt.isRegistered<GlobalStorageContext>() ? getIt<GlobalStorageContext>() : null,
        comObjectInvocationDiagnostics: getIt<IComObjectInvocationDiagnostics>(),
        odbcCredentialSecretStore: getIt<IOdbcCredentialSecretStore>(),
        hubAuthSecretStore: getIt<IHubAuthSecretStore>(),
        tokenSecretStore: getIt<ITokenSecretStore>(),
        secureStorageRuntimeProbe: getIt<SecureStorageRuntimeProbe>(),
      ),
    );
}
