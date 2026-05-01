import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/hub_recovery_auth_coordinator.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:result_dart/result_dart.dart';

class _MockLoadAgentConfig extends Mock implements LoadAgentConfig {}

class _MockLoginUser extends Mock implements LoginUser {}

class _MockRefreshAuthToken extends Mock implements RefreshAuthToken {}

class _MockSaveAuthToken extends Mock implements SaveAuthToken {}

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

void main() {
  late _MockLoadAgentConfig loadAgentConfig;
  late _MockLoginUser loginUser;
  late _MockRefreshAuthToken refreshAuthToken;
  late _MockSaveAuthToken saveAuthToken;
  late _MockAgentConfigRepository configRepository;
  late HubRecoveryAuthCoordinator coordinator;

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
        id: 'cfg',
        serverUrl: 'https://hub.test',
        agentId: 'agent-1',
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
    loadAgentConfig = _MockLoadAgentConfig();
    loginUser = _MockLoginUser();
    refreshAuthToken = _MockRefreshAuthToken();
    saveAuthToken = _MockSaveAuthToken();
    configRepository = _MockAgentConfigRepository();
    coordinator = HubRecoveryAuthCoordinator(
      loadAgentConfig,
      loginUser,
      refreshAuthToken,
      saveAuthToken,
      configRepository,
    );
  });

  test('refreshSession uses persisted refresh token when current session is absent', () async {
    final config = Config(
      id: 'cfg',
      serverUrl: 'https://hub.test',
      agentId: 'agent-1',
      authToken: 'old-access',
      refreshToken: 'old-refresh',
      driverName: 'SQL Server',
      odbcDriverName: 'ODBC Driver 17 for SQL Server',
      connectionString: '',
      username: '',
      databaseName: '',
      host: 'localhost',
      port: 1433,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
    const refreshed = AuthToken(token: 'new-access', refreshToken: 'new-refresh');
    when(() => loadAgentConfig(null)).thenAnswer((_) async => Success(config));
    when(() => refreshAuthToken('https://hub.test', 'old-refresh')).thenAnswer((_) async => const Success(refreshed));
    when(() => saveAuthToken(refreshed)).thenAnswer((_) async => const Success(unit));

    final result = await coordinator.refreshSession('https://hub.test');

    expect(result.isSuccess(), isTrue);
    expect(result.getOrThrow().token, 'new-access');
  });

  test('loginWithStoredCredentials uses persisted username/password and saves token', () async {
    final config = Config(
      id: 'cfg',
      serverUrl: 'https://hub.test',
      agentId: 'agent-1',
      authUsername: 'agent_user',
      authPassword: 'agent_pass',
      driverName: 'SQL Server',
      odbcDriverName: 'ODBC Driver 17 for SQL Server',
      connectionString: '',
      username: '',
      databaseName: '',
      host: 'localhost',
      port: 1433,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );
    const token = AuthToken(token: 'new-access', refreshToken: 'new-refresh');
    when(() => loadAgentConfig(null)).thenAnswer((_) async => Success(config));
    when(() => loginUser('https://hub.test', any())).thenAnswer((_) async => const Success(token));
    when(() => saveAuthToken(token)).thenAnswer((_) async => const Success(unit));

    final result = await coordinator.loginWithStoredCredentials(
      'https://hub.test',
      'agent-1',
    );

    expect(result.isSuccess(), isTrue);
    verify(() => loginUser('https://hub.test', any())).called(1);
  });
}
