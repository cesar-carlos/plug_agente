part of 'plug_dependency_registrar.dart';

void _registerActionsUseCases(GetIt getIt) {
  getIt
    ..registerLazySingleton(
      () => SaveAgentConfig(
        getIt<IAgentConfigRepository>(),
        getIt<ConfigService>(),
        circuitBreakerResetProvider: () =>
            getIt.isRegistered<IOdbcCircuitBreakerReset>()
                ? getIt<IOdbcCircuitBreakerReset>()
                : null,
        metadataCache: getIt<ActiveConfigMetadataCache>(),
        streamingConnectionStringCache: getIt<SqlStreamingConnectionStringCache>(),
      ),
    )
    ..registerLazySingleton(
      () => LoadAgentConfig(getIt<ActiveConfigResolver>()),
    )
    ..registerLazySingleton(
      () => ValidateAgentActionDefinition(
        getIt<AgentActionAdapterRegistry>(),
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
        runtimeExecutionValidator: const AgentActionRuntimeExecutionValidator(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
      ),
    )
    ..registerLazySingleton(
      () => TestAgentActionDefinition(
        getIt<IAgentActionRepository>(),
        getIt<ValidateAgentActionDefinition>(),
      ),
    )
    ..registerLazySingleton(
      () => PreviewAgentActionDefinition(
        getIt<IAgentActionRepository>(),
        getIt<AgentActionAdapterRegistry>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentActionDefinition(
        getIt<IAgentActionRepository>(),
        getIt<ValidateAgentActionDefinition>(),
        getIt<AgentActionDefinitionSnapshotter>(),
        getIt<FeatureFlags>(),
        secretReferenceFingerprinter: getIt<AgentActionSecretReferenceFingerprinter>(),
        preflightSettings: getIt<AgentActionPreflightSettings>(),
      ),
    )
    ..registerLazySingleton(
      () => GetAgentActionDefinition(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListAgentActionDefinitions(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListDeveloperData7Connections(
        getIt<IDeveloperData7ConnectionGateway>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteAgentActionDefinition(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      ValidateAgentActionTrigger.new,
    )
    ..registerLazySingleton(
      () => SaveAgentActionTrigger(
        getIt<IAgentActionRepository>(),
        getIt<ValidateAgentActionTrigger>(),
        getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton(
      () => GetAgentActionTrigger(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListAgentActionTriggers(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton<IAgentActionPortableCodec>(
      AgentActionPortableCodec.new,
    )
    ..registerLazySingleton(
      () => AgentActionBackupSanitizer(codec: getIt<IAgentActionPortableCodec>()),
    )
    ..registerLazySingleton(
      () => ExportAgentActionsBundle(
        getIt<ListAgentActionDefinitions>(),
        getIt<ListAgentActionTriggers>(),
        getIt<AgentActionBackupSanitizer>(),
      ),
    )
    ..registerLazySingleton(
      () => ImportAgentActionsBundle(
        getIt<SaveAgentActionDefinition>(),
        getIt<SaveAgentActionTrigger>(),
        getIt<AgentActionBackupSanitizer>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteAgentActionTrigger(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => SaveAgentActionExecution(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => GetAgentActionExecution(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton<SliceAgentActionCapturedOutput>(
      () => SliceAgentActionCapturedOutput(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => BackfillAgentActionExecutionCorrelation(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListAgentActionExecutions(getIt<IAgentActionRepository>()),
    )
    ..registerLazySingleton(
      () => ListRecentAgentActionRemoteAudit(getIt<IAgentActionRemoteAuditStore>()),
    )
    ..registerLazySingleton(
      () => CleanupExpiredRpcIdempotencyCache(
        getIt<IIdempotencyStore>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => RpcIdempotencyCachePeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupExpiredRpcIdempotencyCache>()(referenceTime: referenceTime),
      ),
    )
    ..registerLazySingleton(
      () => CleanupExpiredAgentActionRemoteAudit(
        getIt<IAgentActionRemoteAuditStore>(),
        retention: getIt<AgentActionRetentionSettings>().remoteAuditRetention,
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionRemoteAuditPeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupExpiredAgentActionRemoteAudit>()(referenceTime: referenceTime),
      ),
    )
    ..registerLazySingleton(
      () => CleanupExpiredElevatedBridgeArtifacts(
        storageContext: getIt<GlobalStorageContext>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedBridgeArtifactsPeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupExpiredElevatedBridgeArtifacts>()(referenceTime: referenceTime),
      ),
    )
    ..registerLazySingleton(
      () => CleanupAgentActionCapturedOutput(
        getIt<IAgentActionRepository>(),
        retention: getIt<AgentActionRetentionSettings>().capturedOutputRetention,
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionCapturedOutputPeriodicPurge(
        ({DateTime? now}) => getIt<CleanupAgentActionCapturedOutput>()(now: now),
      ),
    )
    ..registerLazySingleton(
      () => CleanupAgentActionExecutions(
        getIt<IAgentActionRepository>(),
        retention: getIt<AgentActionRetentionSettings>().executionRetention,
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionExecutionPeriodicPurge(
        ({DateTime? referenceTime}) => getIt<CleanupAgentActionExecutions>()(now: referenceTime),
      ),
    )
    ..registerLazySingleton<IAgentActionOrphanProcessTerminator>(
      () => const AgentActionOrphanProcessTerminator(),
    )
    ..registerLazySingleton(
      () => ReconcileAgentActionExecutions(
        getIt<IAgentActionRepository>(),
        saveExecution: getIt<SaveAgentActionExecution>(),
        orphanProcessTerminator: getIt<IAgentActionOrphanProcessTerminator>(),
      ),
    )
    ..registerLazySingleton(
      () => ApplyAgentActionOnAppExitPolicies(
        getIt<IAgentActionRepository>(),
        getIt<CancelAgentActionExecution>(),
      ),
    )
    ..registerLazySingleton(
      () => CancelAgentActionExecution(
        getIt<IAgentActionRepository>(),
        getIt<AgentActionLocalRunnerRegistry>(),
        executionQueue: getIt<ActionExecutionQueue>(),
        saveExecution: getIt<SaveAgentActionExecution>(),
        metrics: getIt<MetricsCollector>(),
        elevatedCanceller: getIt<IElevatedActionExecutionCanceller>(),
        elevatedAbortRegistry: getIt<ElevatedActionExecutionAbortRegistry>(),
        remoteLifecycleAudit: getIt<AgentActionRemoteLifecycleAuditRecorder>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionDangerousCommandPolicyEnforcer(
        commandSafetyAssessor: getIt<IActionCommandSafetyAssessor>(),
        featureFlags: getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton(AgentActionPreparedExecutionCache.new)
    ..registerLazySingleton(
      () => AgentActionExecutionGateChain(
        repository: getIt<IAgentActionRepository>(),
        runnerRegistry: getIt<AgentActionLocalRunnerRegistry>(),
        runtimeRequestValidator: getIt<AgentActionRuntimeRequestValidator>(),
        runtimeExecutionValidator: const AgentActionRuntimeExecutionValidator(),
        runtimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        featureFlags: getIt<FeatureFlags>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
        dangerousCommandPolicyEnforcer: getIt<AgentActionDangerousCommandPolicyEnforcer>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
        elevatedExecutionService: getIt<ElevatedAgentActionExecutionService>(),
        definitionSnapshotter: getIt<AgentActionDefinitionSnapshotter>(),
        secretReferenceFingerprinter: getIt<AgentActionSecretReferenceFingerprinter>(),
      ),
    )
    ..registerLazySingleton(
      () => RunAgentActionLocally(
        getIt<IAgentActionRepository>(),
        getIt<AgentActionLocalRunnerRegistry>(),
        getIt<Uuid>(),
        executionQueue: getIt<ActionExecutionQueue>(),
        runtimeRequestValidator: getIt<AgentActionRuntimeRequestValidator>(),
        runtimeExecutionValidator: const AgentActionRuntimeExecutionValidator(),
        runtimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        featureFlags: getIt<FeatureFlags>(),
        saveExecution: getIt<SaveAgentActionExecution>(),
        runtimeIdentity: getIt<AgentRuntimeIdentity>(),
        metrics: getIt<MetricsCollector>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        notifyExecution: NotifyAgentActionExecutionIfConfigured(
          getIt<SendNotification>(),
          resolveMessages: agentActionNotificationMessagesForPlatformLocale,
          notificationsSupported: () => getIt<RuntimeCapabilities>().supportsNotifications,
        ),
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
        elevatedExecutionService: getIt<ElevatedAgentActionExecutionService>(),
        remoteLifecycleAudit: getIt<AgentActionRemoteLifecycleAuditRecorder>(),
        definitionSnapshotter: getIt<AgentActionDefinitionSnapshotter>(),
        secretReferenceFingerprinter: getIt<AgentActionSecretReferenceFingerprinter>(),
        dangerousCommandPolicyEnforcer: getIt<AgentActionDangerousCommandPolicyEnforcer>(),
        executionGateChain: getIt<AgentActionExecutionGateChain>(),
        preparedExecutionCache: getIt<AgentActionPreparedExecutionCache>(),
      ),
    )
    ..registerLazySingleton(
      () => DispatchAgentActionTrigger(
        getIt<IAgentActionRepository>(),
        getIt<RunAgentActionLocally>(),
      ),
    )
    ..registerLazySingleton(
      () => RunAgentActionViaRemoteTrigger(
        getIt<IAgentActionRepository>(),
        getIt<DispatchAgentActionTrigger>(),
      ),
    )
    ..registerLazySingleton<IAgentActionSchedulerInstanceLock>(
      () => AgentActionSchedulerInstanceLock(
        storageContext: getIt<GlobalStorageContext>(),
        runtimeIdentity: getIt<AgentRuntimeIdentity>(),
        aclBootstrap: getIt<GlobalStorageAclBootstrap>(),
        metadataReader: const SchedulerLockMetadataReader(),
        processLifetimeChecker: getIt<WindowsProcessLifetimeChecker>(),
        staleLockRecovery: SchedulerStaleLockRecovery(
          metadataReader: const SchedulerLockMetadataReader(),
          processLifetimeChecker: getIt<WindowsProcessLifetimeChecker>(),
          aclBootstrap: getIt<GlobalStorageAclBootstrap>(),
        ),
        failureResolver: SchedulerLockFailureResolver(
          metadataReader: const SchedulerLockMetadataReader(),
        ),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionTriggerScheduler(
        getIt<IAgentActionRepository>(),
        getIt<DispatchAgentActionTrigger>(),
        featureFlags: getIt<FeatureFlags>(),
        schedulerInstanceLock: getIt<IAgentActionSchedulerInstanceLock>(),
      ),
    )
    ..registerLazySingleton(
      () => AgentActionSubsystemCoordinator(
        getIt<AgentActionRuntimeStateGuard>(),
        getIt<AgentActionTriggerScheduler>(),
        getIt<FeatureFlags>(),
      ),
    );
}
