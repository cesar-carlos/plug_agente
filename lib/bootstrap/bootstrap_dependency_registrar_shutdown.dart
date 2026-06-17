part of 'bootstrap_dependency_registrar.dart';

void _registerShutdown(GetIt getIt) {
  getIt.registerLazySingleton<IAppInfrastructureShutdownPort>(
    () => InfrastructureShutdownPort(getIt),
  );
}
