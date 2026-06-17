part of 'bootstrap_dependency_registrar.dart';

void _registerPlayground(GetIt getIt) {
  getIt
    ..registerLazySingleton<SqlExecuteMaterializedResultPolicy>(
      () => const SqlExecuteMaterializedResultPolicy(),
    )
    ..registerLazySingleton(
      () => ExecutePlaygroundQuery(
        getIt<IDatabaseGateway>(),
        getIt<ActiveConfigResolver>(),
        getIt<Uuid>(),
        materializedPolicy: getIt<SqlExecuteMaterializedResultPolicy>(),
      ),
    )
    ..registerLazySingleton(
      () => ExecuteStreamingQuery(
        getIt<IStreamingDatabaseGateway>(),
        getIt<IOdbcConnectionSettings>(),
      ),
    );
}
