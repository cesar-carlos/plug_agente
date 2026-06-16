part of 'plug_dependency_registrar.dart';

void _registerApplicationServices(GetIt getIt) {
  getIt
    ..registerLazySingleton(
      () => QueryNormalizerService(getIt<QueryNormalizer>()),
    )
    ..registerLazySingleton(
      SqlOperationClassifier.new,
    )
    ..registerLazySingleton(
      () => ClientTokenValidationService(getIt<IAuthorizationPolicyResolver>()),
    )
    ..registerLazySingleton(() => ConfigService(getIt<ConfigValidator>()))
    ..registerLazySingleton(() => ConnectToHub(getIt<ConnectionService>()))
    ..registerLazySingleton(
      () => TestDbConnection(getIt<ConnectionService>()),
    )
    ..registerLazySingleton(
      () => CheckOdbcDriver(getIt<IOdbcDriverChecker>()),
    )
    ..registerLazySingleton(
      () => ReloadOdbcRuntimeDependencies(getIt<IOdbcRuntimeReloader>()),
    )
    ..registerLazySingleton(
      () => CheckHubAvailability(getIt<IHubAvailabilityProbe>()),
    );
}
