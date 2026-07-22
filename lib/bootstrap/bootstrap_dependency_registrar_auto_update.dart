part of 'bootstrap_dependency_registrar.dart';

void _registerAutoUpdate(GetIt getIt) {
  getIt
    ..registerLazySingleton<IUpdatePreferencesRepository>(
      () => UpdatePreferencesRepository(settingsStore: getIt<IAppSettingsStore>()),
    )
    ..registerLazySingleton<ISilentUpdateInstaller>(
      () {
        final downloadTimeout = Duration(
          seconds: resolveAutoUpdateDownloadTimeoutSeconds(
            environment: AppEnvironment.snapshot(),
          ),
        );
        return DioSilentUpdateInstaller(
          downloadTimeout: downloadTimeout,
          dioFactory: () => DioFactory.createDio(requestTimeout: downloadTimeout),
        );
      },
    )
    ..registerLazySingleton<IUacDetector>(
      () => Platform.isWindows ? WindowsUacDetector() : const NoopUacDetector(),
    )
    ..registerLazySingleton<IPendingSilentUpdateStore>(
      () => SettingsBackedPendingSilentUpdateStore(
        preferences: getIt<IUpdatePreferencesRepository>(),
      ),
    )
    ..registerLazySingleton<ISilentUpdateLauncherStatusReader>(
      () => const FileSilentUpdateLauncherStatusReader(),
    )
    // Single recorder injected into both orchestrator and coordinator.
    // The old default-construction in each consumer could end up with
    // two recorders writing to the same `auto_update.recent_check_ids`
    // ring buffer and dropping entries on concurrent records.
    ..registerLazySingleton(
      () => UpdateCheckIdRecorder(settingsStore: getIt<IAppSettingsStore>()),
    )
    // Throttled diagnostics gateway. The Plug hub method
    // `agent.autoUpdate.diagnostics.push` remains a **proposta** (Decisao 3
    // of plano_auto_update_evolution.md): schema exists under
    // docs/communication/schemas/, but it is intentionally **not** listed in
    // openrpc.json / rpc.discover until the hub consumes it. Outbound
    // transport is currently a no-op; when the hub ships the method, swap the
    // closure below for a real RPC sender and re-add the OpenRPC entry.
    ..registerLazySingleton<IAutoUpdateDiagnosticsGateway>(
      () => ThrottledAutoUpdateDiagnosticsGateway(
        transport: (payload) async {
          developer.log(
            'auto-update diagnostics push (no-op transport; hub method still in proposta state)',
            name: 'plug_dependency_registrar',
            level: 700,
          );
        },
        agentId: getIt<AgentRuntimeIdentity>().runtimeInstanceId,
      ),
    )
    ..registerLazySingleton<IAutoUpdateOrchestrator>(
      () => AutoUpdateOrchestrator(
        getIt<RuntimeCapabilities>(),
        silentUpdateInstaller: getIt<ISilentUpdateInstaller>(),
        settingsStore: getIt<IAppSettingsStore>(),
        updatePreferencesRepository: getIt<IUpdatePreferencesRepository>(),
        metricsCollector: getIt<MetricsCollector>(),
        diagnosticsGateway: getIt<IAutoUpdateDiagnosticsGateway>(),
        pendingStore: getIt<IPendingSilentUpdateStore>(),
        launcherStatusReader: getIt<ISilentUpdateLauncherStatusReader>(),
        checkIdRecorder: getIt<UpdateCheckIdRecorder>(),
        uacDetector: getIt<IUacDetector>(),
        helperWaitDuration: Duration(
          minutes: resolveAutoUpdateHelperWaitMinutes(
            environment: AppEnvironment.snapshot(),
          ),
        ),
        automaticBootJitterProvider: _autoUpdateBootJitter,
        closeApplicationForSilentUpdate: _closeApplicationForSilentUpdate,
        allowQuitForUpdate: () async {
          if (getIt.isRegistered<WindowManagerService>()) {
            await getIt<WindowManagerService>().allowQuitForUpdate();
          }
        },
      ),
    );
}
