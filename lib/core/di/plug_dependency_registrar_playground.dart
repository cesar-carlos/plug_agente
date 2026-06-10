part of 'plug_dependency_registrar.dart';

void _registerPlayground(GetIt getIt) {
  getIt
    ..registerLazySingleton(
      () => ExecutePlaygroundQuery(
        getIt<IDatabaseGateway>(),
        getIt<ActiveConfigResolver>(),
        getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton(
      () => ExecuteStreamingQuery(
        getIt<IStreamingDatabaseGateway>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    );
}
