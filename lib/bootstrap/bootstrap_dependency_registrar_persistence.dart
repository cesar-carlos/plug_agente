part of 'bootstrap_dependency_registrar.dart';

void _registerPersistence(GetIt getIt) {
  getIt
    ..registerLazySingleton(
      () => AppDatabase(
        databaseFilePath: getIt<GlobalStorageContext>().databaseFilePath,
      ),
    )
    ..registerLazySingleton<ITokenSecretStore>(
      () {
        try {
          return FlutterSecureTokenSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureTokenSecretStore init failed, using NoopTokenSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopTokenSecretStore();
        }
      },
    )
    ..registerLazySingleton<IHubAuthSecretStore>(
      () {
        try {
          return FlutterSecureHubAuthSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureHubAuthSecretStore init failed, using NoopHubAuthSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopHubAuthSecretStore();
        }
      },
    )
    ..registerLazySingleton<IHubSessionStore>(
      () => HubSessionStore(
        getIt<AppDatabase>(),
        authSecretStore: getIt<IHubAuthSecretStore>(),
      ),
    )
    ..registerLazySingleton<IOdbcCredentialSecretStore>(
      () {
        try {
          return FlutterSecureOdbcCredentialSecretStore();
        } on Object catch (e, stackTrace) {
          developer.log(
            'FlutterSecureOdbcCredentialSecretStore init failed, using NoopOdbcCredentialSecretStore',
            name: 'plug_dependency_registrar',
            level: 900,
            error: e,
            stackTrace: stackTrace,
          );
          return NoopOdbcCredentialSecretStore();
        }
      },
    )
    ..registerLazySingleton<IOdbcCredentialStore>(
      () => OdbcCredentialStore(
        getIt<AppDatabase>(),
        credentialSecretStore: getIt<IOdbcCredentialSecretStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ClientTokenLocalDataSource(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<IAgentConfigRepository>(
      () => AgentConfigRepository(
        getIt<AppDatabase>(),
        authSecretStore: getIt<IHubAuthSecretStore>(),
        hubSessionStore: getIt<IHubSessionStore>(),
        odbcCredentialSecretStore: getIt<IOdbcCredentialSecretStore>(),
        odbcCredentialStore: getIt<IOdbcCredentialStore>(),
      ),
    )
    ..registerLazySingleton<IAgentActionRepository>(
      () => AgentActionRepository(getIt<AppDatabase>()),
    );
}
