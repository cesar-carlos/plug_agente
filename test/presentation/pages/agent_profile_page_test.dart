import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/presentation/pages/agent_profile_page.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

class FakeAgentProfile extends Fake implements AgentProfile {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeAgentProfile());
  });

  group('AgentProfilePage', () {
    late MockConfigProvider mockConfigProvider;

    setUp(() {
      mockConfigProvider = MockConfigProvider();
      when(() => mockConfigProvider.currentConfig).thenReturn(_sampleConfig);
      when(() => mockConfigProvider.isLoading).thenReturn(false);
      when(() => mockConfigProvider.error).thenReturn('');
      when(() => mockConfigProvider.loadConfigById(any())).thenAnswer((
        _,
      ) async {
        return;
      });
      when(
        () => mockConfigProvider.saveConfig(),
      ).thenAnswer((_) async => const Success(unit));
      when(() => mockConfigProvider.updateAgentProfile(any())).thenReturn(null);
    });

    testWidgets('shows identity section when config is loaded', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(_buildWidget(mockConfigProvider));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.agentProfilePageTitle), findsOneWidget);
      expect(
        find.text(AppStrings.agentProfileFormSectionTitle),
        findsOneWidget,
      );
      expect(find.text(AppStrings.agentProfileSectionIdentity), findsWidgets);
      expect(find.text(AppStrings.agentProfileSectionContact), findsOneWidget);
      expect(find.text(AppStrings.agentProfileSectionAddress), findsWidgets);
      expect(find.text(AppStrings.agentProfileSectionNotes), findsOneWidget);
      expect(find.text(AppStrings.agentProfileFieldName), findsOneWidget);
      expect(find.text(AppStrings.agentProfileActionSave), findsOneWidget);
    });

    testWidgets('saves profile when tapping save button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(_buildWidget(mockConfigProvider));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(AppStrings.agentProfileActionSave));
      await tester.tap(find.text(AppStrings.agentProfileActionSave));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      verify(() => mockConfigProvider.updateAgentProfile(any())).called(1);
      verify(() => mockConfigProvider.saveConfig()).called(1);
    });
  });
}

Widget _buildWidget(ConfigProvider provider) {
  return FluentApp(
    home: ChangeNotifierProvider<ConfigProvider>.value(
      value: provider,
      child: AgentProfilePage(
        openCnpjClient: OpenCnpjClient(Dio()),
        viaCepClient: ViaCepClient(Dio()),
      ),
    ),
  );
}

final Config _sampleConfig = Config(
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
