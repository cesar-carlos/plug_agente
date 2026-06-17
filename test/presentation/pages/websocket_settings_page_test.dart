import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_operational_readiness_snapshot.dart';
import 'package:plug_agente/application/services/hub_session_coordinator.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/websocket_settings_page.dart';
import 'package:plug_agente/presentation/providers/agent_operational_readiness_provider.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockHubSessionCoordinator extends Mock implements HubSessionCoordinator {}

class MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

class MockConnectionProvider extends Mock with ChangeNotifier implements ConnectionProvider {}

class MockAgentOperationalReadinessProvider extends Mock
    with ChangeNotifier
    implements AgentOperationalReadinessProvider {}

void main() {
  late AppLocalizations enL10n;
  late MockHubSessionCoordinator mockHubSessionCoordinator;

  setUpAll(() async {
    registerFallbackValue(AuthCredentials.test());
    registerFallbackValue('');
    enL10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    mockHubSessionCoordinator = MockHubSessionCoordinator();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('silent token restore does not show auth success modal', (tester) async {
    await getIt.reset();
    getIt.registerSingleton<RuntimeCapabilities>(RuntimeCapabilities.full());
    getIt.registerSingleton<FeatureFlags>(
      FeatureFlags(InMemoryAppSettingsStore()),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final savedConfig = _savedConfig;
    final configProvider = MockConfigProvider();
    final authProvider = AuthProvider(mockHubSessionCoordinator);
    final connectionProvider = MockConnectionProvider();

    when(() => configProvider.loadConfigById(any())).thenAnswer((_) async {});
    when(() => configProvider.isLoading).thenReturn(false);
    when(() => configProvider.currentConfig).thenReturn(savedConfig);
    when(() => configProvider.error).thenReturn('');
    when(configProvider.saveConfig).thenAnswer((_) async => Success(savedConfig));
    when(() => connectionProvider.status).thenReturn(ConnectionStatus.disconnected);
    when(() => connectionProvider.isReconnecting).thenReturn(false);
    when(() => connectionProvider.isConnected).thenReturn(false);
    when(() => connectionProvider.isDbConnected).thenReturn(false);
    when(() => connectionProvider.activeConfigId).thenReturn(savedConfig.id);
    when(() => connectionProvider.error).thenReturn('');

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<ConnectionProvider>.value(value: connectionProvider),
            ChangeNotifierProvider<AgentOperationalReadinessProvider>.value(
              value: _idleAgentOperationalReadinessProvider(),
            ),
          ],
          child: const WebSocketSettingsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    authProvider.restoreToken(
      const AuthToken(token: 't', refreshToken: 'r'),
      silent: true,
      configId: savedConfig.id,
    );
    await tester.pumpAndSettle();

    expect(find.text(enL10n.msgAuthenticatedSuccessfully), findsNothing);
  });
}

AgentOperationalReadinessProvider _idleAgentOperationalReadinessProvider() {
  final mock = MockAgentOperationalReadinessProvider();
  when(() => mock.snapshot).thenReturn(
    const AgentOperationalReadinessSnapshot(
      hubConnected: false,
      hubPhase: HubConnectionPhase.disconnected,
      activeClientTokenCount: 0,
    ),
  );
  return mock;
}

final Config _savedConfig = Config(
  id: 'cfg-1',
  serverUrl: 'https://hub.test',
  agentId: 'agent-1',
  driverName: 'SQL Server',
  odbcDriverName: 'ODBC Driver 17 for SQL Server',
  connectionString: '',
  username: 'u',
  databaseName: 'd',
  host: 'h',
  port: 1433,
  createdAt: DateTime.utc(2024),
  updatedAt: DateTime.utc(2024),
);
