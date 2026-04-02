import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

class MockSaveAgentConfig extends Mock implements SaveAgentConfig {}

class MockLoadAgentConfig extends Mock implements LoadAgentConfig {}

class MockConfigService extends Mock implements ConfigService {}

class MockUuid extends Mock implements Uuid {}

class FakeConfig extends Fake implements Config {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeConfig());
  });

  group('ConfigProvider', () {
    late MockSaveAgentConfig mockSave;
    late MockLoadAgentConfig mockLoad;
    late MockConfigService mockConfigService;
    late MockUuid mockUuid;
    late Config persistedConfig;

    setUp(() {
      mockSave = MockSaveAgentConfig();
      mockLoad = MockLoadAgentConfig();
      mockConfigService = MockConfigService();
      mockUuid = MockUuid();
      persistedConfig = _baseConfig;

      when(() => mockUuid.v4()).thenReturn('generated-id');
      when(
        () => mockConfigService.generateConnectionString(any()),
      ).thenReturn('DRIVER={SQL Server};SERVER=localhost,1433;');
      when(() => mockLoad.call(any())).thenAnswer((_) async {
        return Success(persistedConfig);
      });
      when(() => mockSave.call(any())).thenAnswer((invocation) async {
        persistedConfig = invocation.positionalArguments.first as Config;
        return Success(persistedConfig);
      });
    });

    test(
      'should save and reload agent profile fields without page layer',
      () async {
        final provider = ConfigProvider(
          mockSave,
          mockLoad,
          mockConfigService,
          mockUuid,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final profileResult = AgentProfile.fromFormFields(
          name: 'Empresa Exemplo LTDA',
          tradeName: 'Exemplo',
          document: '11.222.333/0001-81',
          phone: '(11) 3456-7890',
          mobile: '(11) 91234-5678',
          email: 'contato@exemplo.com',
          street: 'Rua Um',
          number: '123',
          district: 'Centro',
          postalCode: '01001-000',
          city: 'Sao Paulo',
          state: 'SP',
          notes: 'Perfil de teste',
        );
        expect(profileResult.isSuccess(), isTrue);

        provider.updateAgentProfile(profileResult.getOrThrow());
        final saveResult = await provider.saveConfig();
        expect(saveResult.isSuccess(), isTrue);

        await provider.loadConfigById(persistedConfig.id);
        final reloaded = provider.currentConfig;
        expect(reloaded, isNotNull);
        expect(reloaded!.nome, equals('Empresa Exemplo LTDA'));
        expect(reloaded.nomeFantasia, equals('Exemplo'));
        expect(reloaded.cnaeCnpjCpf, equals('11222333000181'));
        expect(reloaded.cep, equals('01001000'));
        expect(reloaded.ufMunicipio, equals('SP'));
        expect(reloaded.observacao, equals('Perfil de teste'));
      },
    );
  });
}

final Config _baseConfig = Config(
  id: 'config-1',
  agentId: 'agent-1',
  driverName: 'SQL Server',
  odbcDriverName: 'ODBC Driver 17 for SQL Server',
  connectionString: '',
  username: 'sa',
  password: 'secret',
  databaseName: 'plug',
  host: 'localhost',
  port: 1433,
  nome: 'Base',
  nomeFantasia: 'Base',
  cnaeCnpjCpf: '11222333000181',
  telefone: '1134567890',
  celular: '11912345678',
  email: 'base@empresa.com',
  endereco: 'Rua Base',
  numeroEndereco: '10',
  bairro: 'Centro',
  cep: '01001000',
  nomeMunicipio: 'Sao Paulo',
  ufMunicipio: 'SP',
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
);
