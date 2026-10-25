part of 'bootstrap_dependency_registrar.dart';

void _registerAutoUpdate(GetIt getIt) {
  if (Platform.isWindows) {
    getIt.registerLazySingleton<IInstallationPreparationMonitor>(
      () => WindowsInstallationPreparationMonitor(
        InstallationPreparationService(
          prepareMaintenance: (operation) {
            suppressUpdateForManualInstallation();
            return getIt<BootstrapUpdateMaintenance>().prepare(operation);
          },
          closeApplication: _closeApplicationForSilentUpdate,
          cancelMaintenance: () => getIt<BootstrapUpdateMaintenance>().cancel(),
        ),
        onStateChanged: (state) async {
          if (!getIt.isRegistered<INotificationService>()) return;
          final text = _silentUpdateLocalizations();
          final body = switch (state) {
            InstallationPreparationState.waiting => text.installationPreparationWaiting,
            InstallationPreparationState.closing => text.installationPreparationClosing,
            InstallationPreparationState.blocked => text.installationPreparationBlocked,
            InstallationPreparationState.cancelled => text.installationPreparationCancelled,
            InstallationPreparationState.recoveryRequired => text.installationPreparationRecovery,
          };
          final result = await getIt<INotificationService>().show(title: text.installationPreparationTitle, body: body);
          if (result.isError()) throw result.exceptionOrNull()!;
        },
      ),
      dispose: (monitor) => monitor.stop(),
    );
    getIt
      ..registerLazySingleton(() => BootstrapUpdateMaintenance(getIt))
      ..registerLazySingleton<IPrivilegedUpdater>(WindowsPrivilegedUpdater.new)
      ..registerLazySingleton<IUpdateSecretsSnapshot>(WindowsUpdateSecretsSnapshot.new);
  }
  getIt
    ..registerLazySingleton<IAppcastProbeService>(AppcastProbeService.new)
    ..registerLazySingleton<IUpdateManifestDownloader>(HttpUpdateManifestDownloader.new)
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
        final downloader = DioSilentUpdateInstaller(
          downloadTimeout: downloadTimeout,
          dioFactory: () => DioFactory.createDio(requestTimeout: downloadTimeout),
        );
        if (!Platform.isWindows) return downloader;
        return PrivilegedSilentUpdateInstaller(
          downloader: downloader,
          manifests: getIt<IUpdateManifestDownloader>(),
          updater: getIt<IPrivilegedUpdater>(),
          secrets: getIt<IUpdateSecretsSnapshot>(),
          prepareMaintenance: getIt<BootstrapUpdateMaintenance>().prepare,
          onRecoveryRequired: getIt<BootstrapUpdateMaintenance>().markRecoveryRequired,
          dataDirectory: () async => getIt<GlobalStorageContext>().appDirectoryPath,
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
    // `agent.autoUpdate.diagnostics.push` remains a proposal outside the
    // updater service plan: schema exists under
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
        appcastProbeService: getIt<IAppcastProbeService>(),
        silentUpdateInstaller: getIt<ISilentUpdateInstaller>(),
        manifestDownloader: getIt<IUpdateManifestDownloader>(),
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
