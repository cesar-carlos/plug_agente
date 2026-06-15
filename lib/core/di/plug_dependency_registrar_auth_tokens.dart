part of 'plug_dependency_registrar.dart';

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
    ..registerLazySingleton(
      () => GetClientTokenSecret(getIt<IClientTokenRepository>()),
    )
    ..registerLazySingleton(
      () => UpdateClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
      ),
    )
    ..registerLazySingleton(
      () => RevokeClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
        revokedTokenStore: getIt<IRevokedTokenStore>(),
        featureFlags: getIt<FeatureFlags>(),
      ),
    )
    ..registerLazySingleton(
      () => DeleteClientToken(
        getIt<IClientTokenRepository>(),
        auditStore: getIt<ITokenAuditStore>(),
        decisionCache: getIt<IAuthorizationDecisionCache>(),
        policyCache: getIt<IClientTokenPolicyCache>(),
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
