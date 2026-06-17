part of 'bootstrap_dependency_registrar.dart';

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

  getIt.registerLazySingleton<IStartupPreferencesRepository>(
    () => StartupPreferencesRepository(
      getIt<IAppSettingsStore>(),
      startupService: getIt.isRegistered<IStartupService>() ? getIt<IStartupService>() : null,
    ),
  );

  getIt.registerLazySingleton<IAppPreferencesRepository>(
    () => AppPreferencesRepository(
      settingsStore: getIt<IAppSettingsStore>(),
      startup: getIt<IStartupPreferencesRepository>(),
      updates: getIt<IUpdatePreferencesRepository>(),
    ),
  );

  getIt
    ..registerLazySingleton(() => SyncStartupStatus(getIt<IStartupPreferencesRepository>()))
    ..registerLazySingleton(() => SetStartWithWindows(getIt<IStartupPreferencesRepository>()))
    ..registerLazySingleton(
      () => SetTrayBehaviorPreference(
        getIt<IStartupPreferencesRepository>(),
        windowManagerService: getIt.isRegistered<IWindowManagerService>() ? getIt<IWindowManagerService>() : null,
      ),
    );

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
