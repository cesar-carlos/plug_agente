import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/dtos/agent_profile_hub_sync_result.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/use_cases/fetch_agent_hub_profile.dart';
import 'package:plug_agente/application/use_cases/sync_agent_profile_with_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_coordinator.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_outcome.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:result_dart/result_dart.dart';

class _MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

class _MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class _MockConnectionProvider extends Mock with ChangeNotifier implements ConnectionProvider {}

class _MockSyncAgentProfileWithHub extends Mock implements SyncAgentProfileWithHub {}

class _MockFetchAgentHubProfile extends Mock implements FetchAgentHubProfile {}

class _FakeAgentProfile extends Fake implements AgentProfile {}

void main() {
  late _MockConfigProvider configProvider;
  late _MockAuthProvider authProvider;
  late _MockConnectionProvider connectionProvider;
  late _MockSyncAgentProfileWithHub syncWithHub;
  late _MockFetchAgentHubProfile fetchFromHub;
  late AgentRegisterProfileProvider registerProvider;
  late AgentProfileSaveCoordinator coordinator;

  setUpAll(() {
    registerFallbackValue(_FakeAgentProfile());
  });

  setUp(() {
    configProvider = _MockConfigProvider();
    authProvider = _MockAuthProvider();
    connectionProvider = _MockConnectionProvider();
    syncWithHub = _MockSyncAgentProfileWithHub();
    fetchFromHub = _MockFetchAgentHubProfile();
    registerProvider = AgentRegisterProfileProvider();
    coordinator = AgentProfileSaveCoordinator(
      configProvider: configProvider,
      authProvider: authProvider,
      connectionProvider: connectionProvider,
      syncAgentProfileWithHub: syncWithHub,
      fetchAgentHubProfile: fetchFromHub,
      registerProfileProvider: registerProvider,
    );

    when(() => configProvider.updateAgentProfile(any())).thenReturn(null);
    when(() => connectionProvider.isConnected).thenReturn(true);
  });

  AgentProfile buildProfile() {
    return AgentProfile.fromConfig(_baseConfig).getOrThrow();
  }

  test('returns local failure when saveConfig fails', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Failure(domain.ValidationFailure('local save error')),
    );

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveLocalFailure>());
    verifyNever(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        isHubConnected: any(named: 'isHubConnected'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    );
  });

  test('returns local only when hub is not connected', () async {
    when(() => connectionProvider.isConnected).thenReturn(false);
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(_baseConfig.id)).thenReturn(
      const AuthToken(token: 'token-1', refreshToken: 'r1'),
    );
    when(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        isHubConnected: false,
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => const AgentProfileHubSyncSkipped(AgentProfileHubSyncSkipReason.hubNotConnected),
    );

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveLocalOnly>());
    verify(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        isHubConnected: false,
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    ).called(1);
  });

  test('returns local only outcome when there is no auth token', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(any())).thenReturn(null);

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveLocalOnly>());
  });

  test('returns synced outcome when push succeeds and hub catalog is persisted', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(_baseConfig.id)).thenReturn(
      const AuthToken(token: 'token-1', refreshToken: 'r1'),
    );
    when(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        isHubConnected: any(named: 'isHubConnected'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => const AgentProfileHubSyncSucceeded(
        profileVersion: 7,
        profileUpdatedAt: '2026-05-27T11:00:00Z',
      ),
    );
    when(
      () => configProvider.persistHubProfileCatalogSync(
        profileVersion: any(named: 'profileVersion'),
        profileUpdatedAtIso: any(named: 'profileUpdatedAtIso'),
      ),
    ).thenAnswer((_) async => const Success(unit));

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveSynced>());
    verify(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: _baseConfig.serverUrl,
        agentId: _baseConfig.agentId,
        accessToken: 'token-1',
        isHubConnected: true,
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: _baseConfig.id,
      ),
    ).called(1);
  });

  test('returns catalog persist failure when hub push succeeds but persist fails', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(_baseConfig.id)).thenReturn(
      const AuthToken(token: 'token-1', refreshToken: 'r1'),
    );
    when(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        isHubConnected: any(named: 'isHubConnected'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => const AgentProfileHubSyncSucceeded(profileVersion: 9),
    );
    when(
      () => configProvider.persistHubProfileCatalogSync(
        profileVersion: any(named: 'profileVersion'),
        profileUpdatedAtIso: any(named: 'profileUpdatedAtIso'),
      ),
    ).thenAnswer(
      (_) async => Failure(domain.ValidationFailure('persist failed')),
    );

    final profile = buildProfile();
    final outcome = await coordinator.save(profile);

    expect(outcome, isA<AgentProfileSaveHubCatalogPersistFailure>());
    expect((outcome as AgentProfileSaveHubCatalogPersistFailure).profile, profile);
  });

  test('returns hub partial failure with conflict failure when push returns 409', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(_baseConfig.id)).thenReturn(
      const AuthToken(token: 'token-1', refreshToken: 'r1'),
    );
    when(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        isHubConnected: any(named: 'isHubConnected'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => AgentProfileHubSyncPushFailed(
        domain.ProfileVersionConflictFailure('version conflict'),
      ),
    );

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveHubPartialFailure>());
    final partial = outcome as AgentProfileSaveHubPartialFailure;
    expect(partial.isVersionConflict, isTrue);
    expect(partial.failure, isA<domain.ProfileVersionConflictFailure>());
  });

  test('returns hub partial failure when push fails after local save', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(_baseConfig.id)).thenReturn(
      const AuthToken(token: 'token-1', refreshToken: 'r1'),
    );
    when(
      () => syncWithHub.call(
        profile: any(named: 'profile'),
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        isHubConnected: any(named: 'isHubConnected'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
        configId: any(named: 'configId'),
      ),
    ).thenAnswer(
      (_) async => AgentProfileHubSyncPushFailed(
        domain.NetworkFailure('hub unreachable'),
      ),
    );

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveHubPartialFailure>());
    verifyNever(
      () => configProvider.persistHubProfileCatalogSync(
        profileVersion: any(named: 'profileVersion'),
        profileUpdatedAtIso: any(named: 'profileUpdatedAtIso'),
      ),
    );
  });
}

final Config _baseConfig = Config(
  id: 'config-1',
  agentId: 'agent-1',
  serverUrl: 'https://hub.example.com',
  driverName: 'SQL Server',
  odbcDriverName: 'ODBC Driver 17 for SQL Server',
  connectionString: '',
  username: 'sa',
  password: 'secret',
  databaseName: 'plug',
  host: 'localhost',
  port: 1433,
  nome: 'ACME LTDA',
  nomeFantasia: 'ACME',
  cnaeCnpjCpf: '11222333000181',
  telefone: '1134567890',
  celular: '11987654321',
  email: 'contato@acme.com',
  endereco: 'Rua A',
  numeroEndereco: '100',
  bairro: 'Centro',
  cep: '01001000',
  nomeMunicipio: 'São Paulo',
  ufMunicipio: 'SP',
  observacao: 'Observação inicial',
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);
