import 'package:dio/dio.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/push_agent_profile_to_hub.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/infrastructure/external_services/open_cnpj_client.dart';
import 'package:plug_agente/infrastructure/external_services/via_cep_client.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_profile_page.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

class MockConnectionProvider extends Mock with ChangeNotifier implements ConnectionProvider {}

class MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class MockPushAgentProfileToHub extends Mock implements PushAgentProfileToHub {}

class FakeAgentProfile extends Fake implements AgentProfile {}

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    registerFallbackValue(FakeAgentProfile());
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  group('AgentProfilePage', () {
    late MockConfigProvider mockConfigProvider;
    late MockConnectionProvider mockConnectionProvider;
    late MockAuthProvider mockAuthProvider;
    late MockPushAgentProfileToHub mockPushToHub;

    setUp(() {
      mockConfigProvider = MockConfigProvider();
      mockConnectionProvider = MockConnectionProvider();
      mockAuthProvider = MockAuthProvider();
      mockPushToHub = MockPushAgentProfileToHub();
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
      when(
        () => mockConfigProvider.persistHubProfileCatalogSync(
          profileVersion: any(named: 'profileVersion'),
          profileUpdatedAtIso: any(named: 'profileUpdatedAtIso'),
        ),
      ).thenAnswer((_) async => const Success(unit));
      when(() => mockConnectionProvider.isConnected).thenReturn(false);
      when(() => mockAuthProvider.currentToken).thenReturn(null);
    });

    testWidgets('shows identity section when config is loaded', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        _buildWidget(
          mockConfigProvider,
          mockConnectionProvider,
          mockAuthProvider,
          mockPushToHub,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(ptL10n.navAgentProfile), findsOneWidget);
      expect(
        find.text(ptL10n.agentProfileFormSectionTitle),
        findsOneWidget,
      );
      expect(find.text(ptL10n.agentProfileSectionIdentity), findsWidgets);
      expect(find.text(ptL10n.agentProfileSectionContact), findsOneWidget);
      expect(find.text(ptL10n.agentProfileSectionAddress), findsWidgets);
      expect(find.text(ptL10n.agentProfileSectionNotes), findsOneWidget);
      expect(find.text(ptL10n.agentProfileFieldName), findsOneWidget);
      expect(find.text(ptL10n.agentProfileActionSave), findsOneWidget);
    });

    testWidgets('saves profile when tapping save button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      await tester.pumpWidget(
        _buildWidget(
          mockConfigProvider,
          mockConnectionProvider,
          mockAuthProvider,
          mockPushToHub,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(ptL10n.agentProfileActionSave));
      await tester.tap(find.text(ptL10n.agentProfileActionSave));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      verify(() => mockConfigProvider.updateAgentProfile(any())).called(1);
      verify(() => mockConfigProvider.saveConfig()).called(1);
    });
  });
}

Widget _buildWidget(
  ConfigProvider configProvider,
  ConnectionProvider connectionProvider,
  AuthProvider authProvider,
  PushAgentProfileToHub pushToHub,
) {
  return FluentApp(
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiProvider(
      providers: [
        ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
        ChangeNotifierProvider<ConnectionProvider>.value(value: connectionProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
      ],
      child: AgentProfilePage(
        openCnpjClient: OpenCnpjClient(Dio()),
        viaCepClient: ViaCepClient(Dio()),
        pushAgentProfileToHub: pushToHub,
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
