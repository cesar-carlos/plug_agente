part of 'bootstrap_dependency_registrar.dart';

void _registerAuthTokens(GetIt getIt) {
  getIt
    ..registerLazySingleton(
      () => PushAgentProfileToHub(
        getIt<IAgentHubProfileGateway>(),
        getIt<Uuid>(),
      ),
    )
    ..registerLazySingleton(
      () => FetchAgentHubProfile(getIt<IAgentHubProfileGateway>()),
    )
    ..registerLazySingleton(
      () => SyncAgentProfileWithHub(getIt<PushAgentProfileToHub>()),
    )
    ..registerLazySingleton(() => LoginUser(getIt<AuthService>()))
    ..registerLazySingleton(() => RefreshAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(() => SaveAuthToken(getIt<AuthService>()))
    ..registerLazySingleton(
      () => CreateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => ListClientTokens(getIt<IClientTokenRepository>()),
    )
    ..registerLazySingleton(() => ListClientTokenPage(getIt<IClientTokenRepository>()))
    ..registerLazySingleton(() => CountActiveClientTokens(getIt<IClientTokenRepository>()))
    ..registerLazySingleton(
      () => GetClientTokenSecret(getIt<IClientTokenRepository>()),
    )
    ..registerLazySingleton(
      () => UpdateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => RevokeClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
      ),
    )
    ..registerLazySingleton(
      () => AuthorizeSqlOperation(
        getIt<SqlOperationClassifier>(),
        getIt<ClientTokenValidationService>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        cacheMetrics: getIt<IAuthorizationCacheMetrics>(),
        decisionTtl: ConnectionConstants.authorizationDecisionCacheTtl,
      ),
    );
}
