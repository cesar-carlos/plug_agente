import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_hub_session_store.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_credentials.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_credentials_state.dart';
import 'package:plug_agente/domain/value_objects/hub_stored_session.dart';
import 'package:result_dart/result_dart.dart';

class _MockActiveConfigResolver extends Mock implements ActiveConfigResolver {}

class _MockLoginUser extends Mock implements LoginUser {}

class _MockRefreshAuthToken extends Mock implements RefreshAuthToken {}

class _MockSaveAuthToken extends Mock implements SaveAuthToken {}

class _MockHubSessionStore extends Mock implements IHubSessionStore {}

void main() {
  const configId = 'cfg';
  const serverUrl = 'https://hub.test';
  const agentId = 'agent-1';

  late _MockActiveConfigResolver activeConfigResolver;
  late _MockLoginUser loginUser;
  late _MockRefreshAuthToken refreshAuthToken;
  late _MockSaveAuthToken saveAuthToken;
  late _MockHubSessionStore hubSessionStore;
  late HubSessionCoordinator coordinator;

  setUpAll(() {
    registerFallbackValue(AuthCredentials.test());
    registerFallbackValue(
      const AuthToken(
        token: 'fallback-token',
        refreshToken: 'fallback-refresh',
      ),
    );
    registerFallbackValue(
      Config(
        id: configId,
        serverUrl: serverUrl,
        agentId: agentId,
        driverName: 'SQL Server',
        odbcDriverName: 'ODBC Driver 17 for SQL Server',
        connectionString: '',
        username: '',
        databaseName: '',
        host: 'localhost',
        port: 1433,
        createdAt: DateTime(2025),
        updatedAt: DateTime(2025),
      ),
    );
  });

  setUp(() {
    activeConfigResolver = _MockActiveConfigResolver();
    loginUser = _MockLoginUser();
    refreshAuthToken = _MockRefreshAuthToken();
    saveAuthToken = _MockSaveAuthToken();
    hubSessionStore = _MockHubSessionStore();
    coordinator = HubSessionCoordinator(
      activeConfigResolver,
      loginUser,
      refreshAuthToken,
      saveAuthToken,
      hubSessionStore,
    );
  });

  test('refreshSession uses persisted refresh token when current session is absent', () async {
    const refreshed = AuthToken(token: 'new-access', refreshToken: 'new-refresh');
    when(() => hubSessionStore.readSession(configId)).thenAnswer(
      (_) async => const Success(
        HubStoredSession(
          token: AuthToken(
            token: 'old-access',
            refreshToken: 'old-refresh',
          ),
        ),
      ),
    );
    when(() => refreshAuthToken(serverUrl, 'old-refresh'))
        .thenAnswer((_) async => const Success(refreshed));
    when(() => hubSessionStore.writeSessionTokens(configId, refreshed))
        .thenAnswer((_) async => const Success(unit));
    when(() => saveAuthToken(configId, refreshed))
        .thenAnswer((_) async => const Success(unit));

    final result = await coordinator.refreshSession(
      serverUrl,
      configId: configId,
    );

    expect(result.isSuccess(), isTrue);
    expect(result.getOrThrow().token, 'new-access');
    verify(() => hubSessionStore.writeSessionTokens(configId, refreshed)).called(1);
    verify(() => saveAuthToken(configId, refreshed)).called(1);
  });

  test('loginWithStoredCredentials uses persisted username/password and saves token', () async {
    const token = AuthToken(token: 'new-access', refreshToken: 'new-refresh');
    when(() => hubSessionStore.readStoredCredentials(configId)).thenAnswer(
      (_) async => const Success(
        HubStoredCredentialsState(
          credentials: HubStoredCredentials(
            username: 'agent_user',
            password: 'agent_pass',
          ),
        ),
      ),
    );
    when(() => loginUser(serverUrl, any())).thenAnswer((_) async => const Success(token));
    when(() => hubSessionStore.writeSessionTokens(configId, token))
        .thenAnswer((_) async => const Success(unit));
    when(() => saveAuthToken(configId, token)).thenAnswer((_) async => const Success(unit));

    final result = await coordinator.loginWithStoredCredentials(
      serverUrl,
      agentId,
      configId: configId,
    );

    expect(result.isSuccess(), isTrue);
    verify(() => loginUser(serverUrl, any())).called(1);
    verify(() => hubSessionStore.writeSessionTokens(configId, token)).called(1);
    verify(() => saveAuthToken(configId, token)).called(1);
  });

  test('bootstrapAutoSession prefers persisted token before stored credentials', () async {
    when(() => hubSessionStore.readSession(configId)).thenAnswer(
      (_) async => const Success(
        HubStoredSession(
          token: AuthToken(
            token: 'persisted-access',
            refreshToken: 'persisted-refresh',
          ),
        ),
      ),
    );

    final result = await coordinator.bootstrapAutoSession(
      configId: configId,
      serverUrl: serverUrl,
      agentId: agentId,
    );

    expect(result.isSuccess(), isTrue);
    expect(result.getOrThrow().source, HubBootstrapSource.persistedToken);
    verifyNever(() => loginUser(any(), any()));
  });

  test('clearStoredSession only clears tokens for the requested config', () async {
    when(
      () => hubSessionStore.clearSession(configId),
    ).thenAnswer((_) async => const Success(unit));

    final result = await coordinator.clearStoredSession(configId);

    expect(result.isSuccess(), isTrue);
    verify(() => hubSessionStore.clearSession(configId)).called(1);
  });
}
