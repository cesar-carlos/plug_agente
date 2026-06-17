part of 'bootstrap_dependency_registrar.dart';

void _registerFoundation(GetIt getIt) {
  getIt
    ..registerLazySingleton(IcaclsCommandRunner.new)
    ..registerLazySingleton(GlobalStorageAclMarkerStore.new)
    ..registerLazySingleton(
      () => GlobalStorageDirectoryAclNormalizer(
        commandRunner: getIt<IcaclsCommandRunner>(),
      ),
    )
    ..registerLazySingleton(
      () => GlobalStorageAclBootstrap(
        normalizer: getIt<GlobalStorageDirectoryAclNormalizer>(),
        markerStore: getIt<GlobalStorageAclMarkerStore>(),
      ),
    )
    ..registerLazySingleton<IGlobalStorageAclBootstrap>(
      () => getIt<GlobalStorageAclBootstrap>(),
    )
    ..registerLazySingleton(WindowsProcessLifetimeChecker.new)
    ..registerLazySingleton<IGlobalStorageHealthSnapshotBuilder>(
      () => GlobalStorageHealthSnapshotBuilder(
        aclBootstrap: getIt<GlobalStorageAclBootstrap>(),
        markerStore: getIt<GlobalStorageAclMarkerStore>(),
      ),
    )
    ..registerLazySingleton(ConfigValidator.new)
    ..registerLazySingleton(QueryNormalizer.new)
    ..registerLazySingleton(SocketDataSource.new);
}
