part of 'bootstrap_dependency_registrar.dart';

void registerPlugStartupServices(
  GetIt getIt,
  RuntimeCapabilities capabilities,
) {
  if (Platform.isWindows) {
    developer.log(
      'Registering AutoStartService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<IStartupService>(
      AutoStartService.new,
    );
  }

  getIt.registerLazySingleton<IStartupPreferencesRepository>(
    () => StartupPreferencesRepository(
      getIt<IAppSettingsStore>(),
      startupService: getIt.isRegistered<IStartupService>() ? getIt<IStartupService>() : null,
    ),
  );

  getIt
    ..registerLazySingleton(() => SyncStartupStatus(getIt<IStartupPreferencesRepository>()))
    ..registerLazySingleton(() => SetStartWithWindows(getIt<IStartupPreferencesRepository>()))
    ..registerLazySingleton(
      () => EnsureStartupLaunchConfigurationAtBoot(getIt<IStartupPreferencesRepository>()),
    )
    ..registerLazySingleton(
      () => SetTrayBehaviorPreference(
        getIt<IStartupPreferencesRepository>(),
        windowManagerService: getIt.isRegistered<IWindowManagerService>() ? getIt<IWindowManagerService>() : null,
      ),
    );

  if (capabilities.supportsWindowManager) {
    developer.log(
      'Registering WindowManagerService',
      name: 'plug_dependency_registrar',
    );
    getIt.registerLazySingleton<WindowManagerService>(WindowManagerService.new);
    getIt.registerLazySingleton<IWindowManagerService>(() => getIt<WindowManagerService>());
  }
}
