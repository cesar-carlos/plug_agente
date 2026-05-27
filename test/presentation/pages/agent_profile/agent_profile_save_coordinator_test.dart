import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_register_profile_provider.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/agent_hub_profile_push_result.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_coordinator.dart';
import 'package:plug_agente/presentation/pages/agent_profile/agent_profile_save_outcome.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:result_dart/result_dart.dart';

class _MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

class _MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class _MockPushAgentProfileToHub extends Mock implements PushAgentProfileToHub {}

class _FakeAgentProfile extends Fake implements AgentProfile {}

void main() {
  late _MockConfigProvider configProvider;
  late _MockAuthProvider authProvider;
  late _MockPushAgentProfileToHub pushToHub;
  late AgentRegisterProfileProvider registerProvider;
  late AgentProfileSaveCoordinator coordinator;

  setUpAll(() {
    registerFallbackValue(_FakeAgentProfile());
  });

  setUp(() {
    configProvider = _MockConfigProvider();
    authProvider = _MockAuthProvider();
    pushToHub = _MockPushAgentProfileToHub();
    registerProvider = AgentRegisterProfileProvider();
    coordinator = AgentProfileSaveCoordinator(
      configProvider: configProvider,
      authProvider: authProvider,
      pushAgentProfileToHub: pushToHub,
      registerProfileProvider: registerProvider,
    );

    when(() => configProvider.updateAgentProfile(any())).thenReturn(null);
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
    expect(
      (outcome as AgentProfileSaveLocalFailure).errorMessage,
      equals('local save error'),
    );
    verifyNever(
      () => pushToHub.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    );
  });

  test('returns local only outcome when there is no auth token', () async {
    when(() => configProvider.saveConfig()).thenAnswer(
      (_) async => Success(_baseConfig),
    );
    when(() => configProvider.currentConfig).thenReturn(_baseConfig);
    when(() => authProvider.currentTokenForConfig(any())).thenReturn(null);

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveLocalOnly>());
    verifyNever(
      () => pushToHub.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    );
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
      () => pushToHub.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    ).thenAnswer(
      (_) async => const Success(
        AgentHubProfilePushResult(profileVersion: 7, profileUpdatedAt: '2026-05-27T11:00:00Z'),
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
      () => configProvider.persistHubProfileCatalogSync(
        profileVersion: 7,
        profileUpdatedAtIso: '2026-05-27T11:00:00Z',
      ),
    ).called(1);
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
      () => pushToHub.call(
        serverUrl: any(named: 'serverUrl'),
        agentId: any(named: 'agentId'),
        accessToken: any(named: 'accessToken'),
        profile: any(named: 'profile'),
        expectedProfileVersion: any(named: 'expectedProfileVersion'),
      ),
    ).thenAnswer(
      (_) async => Failure(domain.NetworkFailure('hub unreachable')),
    );

    final outcome = await coordinator.save(buildProfile());

    expect(outcome, isA<AgentProfileSaveHubPartialFailure>());
    expect(
      (outcome as AgentProfileSaveHubPartialFailure).hubErrorMessage,
      equals('hub unreachable'),
    );
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
