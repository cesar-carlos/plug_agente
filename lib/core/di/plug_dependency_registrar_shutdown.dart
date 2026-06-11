part of 'plug_dependency_registrar.dart';

void _registerShutdown(GetIt getIt) {
  getIt.registerLazySingleton<IAppInfrastructureShutdownPort>(
    () => InfrastructureShutdownPort(getIt),
  );
}
