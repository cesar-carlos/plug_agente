part of 'plug_dependency_registrar.dart';

void _registerActionsInfrastructure(GetIt getIt) {
  getIt
    ..registerLazySingleton(
      () => ActiveConfigResolver(
        getIt<IAgentConfigRepository>(),
        getIt<IAppSettingsStore>(),
        circuitBreakerResetProvider: () =>
            getIt.isRegistered<IOdbcCircuitBreakerReset>()
                ? getIt<IOdbcCircuitBreakerReset>()
                : null,
      ),
    )
    ..registerLazySingleton(ProtocolNegotiator.new)
    ..registerLazySingleton<IProtocolNegotiator>(getIt.get<ProtocolNegotiator>)
    ..registerLazySingleton(ProtocolMetricsCollector.new)
    ..registerLazySingleton<IProtocolMetricsCollector>(
      getIt.get<ProtocolMetricsCollector>,
    )
    ..registerLazySingleton(AuthorizationMetricsCollector.new)
    ..registerLazySingleton<IAuthorizationMetricsCollector>(
      getIt.get<AuthorizationMetricsCollector>,
    )
    ..registerLazySingleton(DeprecationMetricsCollector.new)
    ..registerLazySingleton<IDeprecationMetricsCollector>(
      getIt.get<DeprecationMetricsCollector>,
    )
    ..registerLazySingleton(ActionPathValidator.new)
    ..registerLazySingleton(
      () => DeveloperData7ConfigLocator(
        pathValidator: getIt<ActionPathValidator>(),
      ),
    )
    ..registerLazySingleton(DeveloperData7ConnectionCatalog.new)
    ..registerLazySingleton(
      () => DeveloperData7DefinitionResolver(
        pathValidator: getIt<ActionPathValidator>(),
        configLocator: getIt<DeveloperData7ConfigLocator>(),
        connectionCatalog: getIt<DeveloperData7ConnectionCatalog>(),
      ),
    )
    ..registerLazySingleton<IDeveloperData7ConnectionGateway>(
      () => DeveloperData7ConnectionGateway(
        configLocator: getIt<DeveloperData7ConfigLocator>(),
        connectionCatalog: getIt<DeveloperData7ConnectionCatalog>(),
      ),
    )
    ..registerLazySingleton<ComObjectInvocationRegistry>(
      ComObjectInvocationBootstrap.createRegistry,
    )
    ..registerLazySingleton<IComObjectInvocationDiagnostics>(
      () => ComObjectInvocationDiagnostics(getIt<ComObjectInvocationRegistry>()),
    )
    ..registerLazySingleton<ActionCommandSafetyValidator>(() => const ActionCommandSafetyValidator())
    ..registerLazySingleton<IActionCommandSafetyAssessor>(() => getIt<ActionCommandSafetyValidator>())
    ..registerLazySingleton<IAgentActionsBundleFileGateway>(() => const AgentActionsBundleFileGateway())
    ..registerLazySingleton<ActionCommandNormalizer>(
      () => ActionCommandNormalizer(
        commandSafetyValidator: getIt<ActionCommandSafetyValidator>(),
        featureFlags: getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton<AgentActionAdapterRegistry>(
      () => AgentActionAdapterRegistry([
        CommandLineActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        ExecutableActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        ScriptActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        JarActionAdapter(
          commandNormalizer: getIt<ActionCommandNormalizer>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        EmailActionAdapter(
          pathValidator: getIt<ActionPathValidator>(),
          secretStore: getIt<IAgentActionSecretStore>(),
        ),
        ComObjectActionAdapter(
          invocationRegistry: getIt<ComObjectInvocationRegistry>(),
          pathValidator: getIt<ActionPathValidator>(),
        ),
        DeveloperData7ActionAdapter(
          definitionResolver: getIt<DeveloperData7DefinitionResolver>(),
        ),
      ]),
    )
    ..registerLazySingleton(
      () => ActionProcessStdinSetup(
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
      ),
    )
    ..registerLazySingleton<CommandLineActionProcessRunner>(
      () => CommandLineActionProcessRunner(
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        stdinSetup: getIt<ActionProcessStdinSetup>(),
      ),
    )
    ..registerLazySingleton<ExecutableActionProcessRunner>(
      () => ExecutableActionProcessRunner(
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        stdinSetup: getIt<ActionProcessStdinSetup>(),
      ),
    )
    ..registerLazySingleton<ScriptActionProcessRunner>(
      () => ScriptActionProcessRunner(
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        stdinSetup: getIt<ActionProcessStdinSetup>(),
      ),
    )
    ..registerLazySingleton<JarActionProcessRunner>(
      () => JarActionProcessRunner(
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        stdinSetup: getIt<ActionProcessStdinSetup>(),
      ),
    )
    ..registerLazySingleton<EmailActionMailerRunner>(
      () => EmailActionMailerRunner(
        pathValidator: getIt<ActionPathValidator>(),
        secretStore: getIt<IAgentActionSecretStore>(),
      ),
    )
    ..registerLazySingleton<ComObjectActionRunner>(
      () => ComObjectActionRunner(
        invocationRegistry: getIt<ComObjectInvocationRegistry>(),
        pathValidator: getIt<ActionPathValidator>(),
      ),
    )
    ..registerLazySingleton<DeveloperData7ProcessRunner>(
      () => DeveloperData7ProcessRunner(
        adapterRegistry: getIt<AgentActionAdapterRegistry>(),
        environmentResolver: getIt<ActionEnvironmentResolver>(),
        operationalProfileResolver: const AgentOperationalProfileResolver(),
        stdinSetup: getIt<ActionProcessStdinSetup>(),
      ),
    )
    ..registerLazySingleton<ActionExecutionQueue>(
      () => ActionExecutionQueue(metrics: getIt<MetricsCollector>()),
    )
    ..registerLazySingleton<IAgentActionSecretStore>(
      () {
        try {
          return FlutterSecureAgentActionSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureAgentActionSecretStore init failed, using NoopAgentActionSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return const NoopAgentActionSecretStore();
        }
      },
    )
    ..registerLazySingleton(
      () => AgentActionSecretPlaceholderResolver(
        secretStore: getIt<IAgentActionSecretStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ActionEnvironmentResolver(
        secretPlaceholderResolver: getIt<AgentActionSecretPlaceholderResolver>(),
      ),
    )
    ..registerLazySingleton(
      () => SaveAgentActionSecret(getIt<IAgentActionSecretStore>()),
    )
    ..registerLazySingleton(
      () => DeleteAgentActionSecret(getIt<IAgentActionSecretStore>()),
    )
    ..registerLazySingleton<AgentActionRuntimeRequestValidator>(
      AgentActionRuntimeRequestValidator.new,
    )
    ..registerLazySingleton<AgentActionDefinitionSnapshotter>(
      AgentActionDefinitionSnapshotter.new,
    )
    ..registerLazySingleton(
      () => AgentActionSecretReferenceFingerprinter(getIt<IAgentActionSecretStore>()),
    )
    ..registerLazySingleton<AgentActionRuntimeStateGuard>(
      () => AgentActionRuntimeStateGuard(getIt<FeatureFlags>()),
    )
    ..registerLazySingleton(ElevatedActionRunnerReadinessService.new)
    ..registerLazySingleton<IAgentActionsRemoteCapabilityProvider>(
      () => AgentActionsRemoteCapabilityProvider(
        runtimeStateGuard: getIt<AgentActionRuntimeStateGuard>(),
        elevatedRunnerReadiness: getIt<ElevatedActionRunnerReadinessService>(),
      ),
    )
    ..registerLazySingleton(ElevatedActionExecutionAbortRegistry.new)
    ..registerLazySingleton(
      () => ElevatedActionRunnerInstaller(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton(
      () => PrepareElevatedActionRunner(
        getIt<ElevatedActionRunnerInstaller>(),
        getIt<ElevatedActionRunnerReadinessService>(),
        getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionRequestProtector(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionExecutionMaterializer(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton<IElevatedActionRunnerBridge>(
      () => ElevatedActionRunnerBridge(
        requestProtector: getIt<ElevatedActionRequestProtector>(),
        materializer: getIt<ElevatedActionExecutionMaterializer>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionStatusFileSyncer(
        storageContext: getIt<GlobalStorageContext>(),
        metrics: getIt<MetricsCollector>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedActionStatusFileWriter(
        storageContext: getIt<GlobalStorageContext>(),
      ),
    )
    ..registerLazySingleton<IElevatedActionExecutionCanceller>(
      () => ElevatedActionExecutionCanceller(
        storageContext: getIt<GlobalStorageContext>(),
        statusFileWriter: getIt<ElevatedActionStatusFileWriter>(),
      ),
    )
    ..registerLazySingleton(
      () => ElevatedAgentActionExecutionService(
        bridge: getIt<IElevatedActionRunnerBridge>(),
        statusFileSyncer: getIt<ElevatedActionStatusFileSyncer>(),
        readiness: getIt<ElevatedActionRunnerReadinessService>(),
        abortRegistry: getIt<ElevatedActionExecutionAbortRegistry>(),
      ),
    )
    ..registerLazySingleton<AgentActionLocalRunnerRegistry>(
      () => AgentActionLocalRunnerRegistry([
        getIt<CommandLineActionProcessRunner>(),
        getIt<ExecutableActionProcessRunner>(),
        getIt<ScriptActionProcessRunner>(),
        getIt<JarActionProcessRunner>(),
        getIt<EmailActionMailerRunner>(),
        getIt<ComObjectActionRunner>(),
        getIt<DeveloperData7ProcessRunner>(),
      ]),
    )
    ..registerLazySingleton(
      () => AgentRegisterProfileProvider(
        activeConfigResolver: getIt<ActiveConfigResolver>(),
      ),
    )
    ..registerLazySingleton(() => const Uuid());
}
