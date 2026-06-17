import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_operational_readiness_snapshot.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/core/config/payload_signing_config.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/auth_token.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/websocket_config_section.dart';
import 'package:plug_agente/presentation/pages/websocket_settings/websocket_config_form_controller.dart';
import 'package:plug_agente/presentation/providers/agent_operational_readiness_provider.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockConfigProvider extends Mock with ChangeNotifier implements ConfigProvider {}

class MockAuthProvider extends Mock with ChangeNotifier implements AuthProvider {}

class MockConnectionProvider extends Mock with ChangeNotifier implements ConnectionProvider {}

class MockAgentOperationalReadinessProvider extends Mock
    with ChangeNotifier
    implements AgentOperationalReadinessProvider {}

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    registerFallbackValue(AuthCredentials.test());
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('orchestration via WebSocketConfigController', () {
    testWidgets('login persists current form before authenticating', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final formController = WebsocketConfigFormController();
      addTearDown(formController.dispose);
      formController.serverUrlController.text = 'https://hub.test';
      formController.agentIdController.text = 'agent-1';
      formController.authUsernameController.text = 'agent_user';
      formController.authPasswordController.text = 'agent_pass';

      final configProvider = MockConfigProvider();
      final authProvider = MockAuthProvider();
      final connectionProvider = MockConnectionProvider();
      final savedConfig = _savedConfig;

      when(configProvider.saveConfig).thenAnswer(
        (_) async => Success(savedConfig),
      );
      when(() => configProvider.isLoading).thenReturn(false);
      when(() => configProvider.currentConfig).thenReturn(savedConfig);
      when(() => authProvider.status).thenReturn(AuthStatus.unauthenticated);
      when(
        () => authProvider.isAuthenticatedForConfig(savedConfig.id),
      ).thenReturn(false);
      when(() => authProvider.error).thenReturn('');
      when(
        () => authProvider.login(
          configId: savedConfig.id,
          serverUrl: savedConfig.serverUrl,
          credentials: any(named: 'credentials'),
        ),
      ).thenAnswer((_) async {});
      when(() => connectionProvider.status).thenReturn(ConnectionStatus.disconnected);
      when(() => connectionProvider.isReconnecting).thenReturn(false);
      when(() => connectionProvider.isConnected).thenReturn(false);
      when(() => connectionProvider.isDbConnected).thenReturn(false);

      await tester.pumpWidget(
        _buildWidget(
          formController: formController,
          configProvider: configProvider,
          authProvider: authProvider,
          connectionProvider: connectionProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.wsButtonLogin));
      await tester.pumpAndSettle();

      verifyInOrder([
        configProvider.saveConfig,
        () => authProvider.login(
          configId: savedConfig.id,
          serverUrl: savedConfig.serverUrl,
          credentials: any(named: 'credentials'),
        ),
      ]);
    });

    testWidgets('connect persists current form before opening socket', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final formController = WebsocketConfigFormController();
      addTearDown(formController.dispose);
      formController.serverUrlController.text = 'https://hub.test';
      formController.agentIdController.text = 'agent-1';

      final configProvider = MockConfigProvider();
      final authProvider = MockAuthProvider();
      final connectionProvider = MockConnectionProvider();
      final savedConfig = _savedConfig;

      when(configProvider.saveConfig).thenAnswer(
        (_) async => Success(savedConfig),
      );
      when(() => configProvider.isLoading).thenReturn(false);
      when(() => configProvider.currentConfig).thenReturn(savedConfig);
      when(() => authProvider.status).thenReturn(AuthStatus.authenticated);
      when(
        () => authProvider.isAuthenticatedForConfig(savedConfig.id),
      ).thenReturn(true);
      when(
        () => authProvider.tokenForConfig(savedConfig.id),
      ).thenReturn(const AuthToken(token: 'access', refreshToken: 'refresh'));
      when(() => authProvider.error).thenReturn('');
      when(() => connectionProvider.status).thenReturn(ConnectionStatus.disconnected);
      when(() => connectionProvider.isReconnecting).thenReturn(false);
      when(() => connectionProvider.isConnected).thenReturn(false);
      when(() => connectionProvider.isDbConnected).thenReturn(false);
      when(
        () => connectionProvider.connect(
          savedConfig.serverUrl,
          savedConfig.agentId,
          configId: savedConfig.id,
          authToken: 'access',
        ),
      ).thenAnswer((_) async => const Success(unit));

      await tester.pumpWidget(
        _buildWidget(
          formController: formController,
          configProvider: configProvider,
          authProvider: authProvider,
          connectionProvider: connectionProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(ptL10n.wsButtonConnect));
      await tester.tap(find.text(ptL10n.wsButtonConnect));
      await tester.pumpAndSettle();

      verifyInOrder([
        configProvider.saveConfig,
        () => connectionProvider.connect(
          savedConfig.serverUrl,
          savedConfig.agentId,
          configId: savedConfig.id,
          authToken: 'access',
        ),
      ]);
    });

    testWidgets('connect does not reuse token from another config', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final formController = WebsocketConfigFormController();
      addTearDown(formController.dispose);
      formController.serverUrlController.text = 'https://hub.test';
      formController.agentIdController.text = 'agent-1';

      final configProvider = MockConfigProvider();
      final authProvider = MockAuthProvider();
      final connectionProvider = MockConnectionProvider();
      final savedConfig = _savedConfig;

      when(configProvider.saveConfig).thenAnswer(
        (_) async => Success(savedConfig),
      );
      when(() => configProvider.isLoading).thenReturn(false);
      when(() => configProvider.currentConfig).thenReturn(savedConfig);
      when(() => authProvider.status).thenReturn(AuthStatus.authenticated);
      when(
        () => authProvider.isAuthenticatedForConfig(savedConfig.id),
      ).thenReturn(false);
      when(() => authProvider.tokenForConfig(savedConfig.id)).thenReturn(null);
      when(() => authProvider.error).thenReturn('');
      when(() => connectionProvider.status).thenReturn(ConnectionStatus.disconnected);
      when(() => connectionProvider.isReconnecting).thenReturn(false);
      when(() => connectionProvider.isConnected).thenReturn(false);
      when(() => connectionProvider.isDbConnected).thenReturn(false);

      await tester.pumpWidget(
        _buildWidget(
          formController: formController,
          configProvider: configProvider,
          authProvider: authProvider,
          connectionProvider: connectionProvider,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(ptL10n.wsButtonConnect));
      await tester.tap(find.text(ptL10n.wsButtonConnect));
      await tester.pumpAndSettle();

      verify(configProvider.saveConfig).called(1);
      verifyNever(
        () => connectionProvider.connect(
          any(),
          any(),
          configId: any(named: 'configId'),
          authToken: any(named: 'authToken'),
        ),
      );
    });
  });

  group('outbound compression section', () {
    testWidgets('initial dropdown reflects persisted compression mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setOutboundCompressionMode(OutboundCompressionMode.gzip);

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(ptL10n.wsOutboundCompressionGzip), findsOneWidget);
    });

    testWidgets('selecting "off" persists feature_enable_compression=false', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final store = InMemoryAppSettingsStore();
      final flags = FeatureFlags(store);
      await flags.setOutboundCompressionMode(OutboundCompressionMode.gzip);

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text(ptL10n.wsOutboundCompressionGzip));
      await tester.tap(find.text(ptL10n.wsOutboundCompressionGzip));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.wsOutboundCompressionOff).last);
      await tester.pumpAndSettle();

      expect(flags.outboundCompressionMode, OutboundCompressionMode.none);
      expect(store.getBool('feature_enable_compression'), isFalse);
    });
  });

  group('payload signing section', () {
    testWidgets('renders OK without InfoBar when two keys are configured', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final config = PayloadSigningConfig(
        activeKeyId: 'v2',
        keys: const <String, String>{'v1': 'old', 'v2': 'new'},
        source: PayloadSigningConfigSource.environmentAndSecureStorage,
      );

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          payloadSigningConfig: config,
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(InfoBar), findsNothing);
      expect(
        find.textContaining(ptL10n.wsPayloadSigningRotationReady, findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          ptL10n.wsPayloadSigningSourceEnvironmentAndSecureStorage,
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders warning InfoBar when only a single key is configured', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final config = PayloadSigningConfig(
        activeKeyId: 'v1',
        keys: const <String, String>{'v1': 'secret'},
        source: PayloadSigningConfigSource.secureStorage,
      );

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          payloadSigningConfig: config,
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      final infoBar = tester.widget<InfoBar>(find.byType(InfoBar));
      expect(infoBar.severity, InfoBarSeverity.warning);
      expect(find.text(ptL10n.wsPayloadSigningStatusWarning), findsOneWidget);
      expect(
        find.text(ptL10n.wsPayloadSigningIssueRotationSingleKey),
        findsOneWidget,
      );
      expect(
        find.textContaining(ptL10n.wsPayloadSigningRotationSingleKey, findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('renders error InfoBar when signing is enabled without a key', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnablePayloadSigning(true);

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          payloadSigningConfig: PayloadSigningConfig.empty(),
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      final infoBar = tester.widget<InfoBar>(find.byType(InfoBar));
      expect(infoBar.severity, InfoBarSeverity.error);
      expect(find.text(ptL10n.wsPayloadSigningStatusError), findsOneWidget);
      expect(
        find.text(ptL10n.wsPayloadSigningIssueEnabledWithoutKey),
        findsOneWidget,
      );
    });

    testWidgets('toggling outgoing signing persists the new value', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final config = PayloadSigningConfig(
        activeKeyId: 'v1',
        keys: const <String, String>{'v1': 'old', 'v2': 'new'},
      );

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          payloadSigningConfig: config,
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      expect(flags.enablePayloadSigning, isFalse);
      await tester.ensureVisible(find.text(ptL10n.wsPayloadSigningToggleOutgoing));
      await tester.tap(find.text(ptL10n.wsPayloadSigningToggleOutgoing));
      await tester.pumpAndSettle();

      expect(flags.enablePayloadSigning, isTrue);
    });
  });

  group('client token policy section', () {
    testWidgets('toggle starts on by default and persists off', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flags = FeatureFlags(InMemoryAppSettingsStore());

      await tester.pumpWidget(
        _buildWidget(
          featureFlags: flags,
          configProvider: _idleConfigProvider(),
          authProvider: _idleAuthProvider(),
          connectionProvider: _idleConnectionProvider(),
        ),
      );
      await tester.pumpAndSettle();

      expect(flags.enableClientTokenPolicyIntrospection, isTrue);

      await tester.ensureVisible(
        find.text(ptL10n.wsFieldClientTokenPolicyIntrospection),
      );
      await tester.tap(
        find.text(ptL10n.wsFieldClientTokenPolicyIntrospection),
      );
      await tester.pumpAndSettle();

      expect(flags.enableClientTokenPolicyIntrospection, isFalse);
    });
  });
}

ConfigProvider _idleConfigProvider() {
  final mock = MockConfigProvider();
  when(() => mock.isLoading).thenReturn(false);
  when(() => mock.currentConfig).thenReturn(_savedConfig);
  return mock;
}

AuthProvider _idleAuthProvider() {
  final mock = MockAuthProvider();
  when(() => mock.status).thenReturn(AuthStatus.unauthenticated);
  when(() => mock.error).thenReturn('');
  when(() => mock.isAuthenticatedForConfig(any())).thenReturn(false);
  return mock;
}

ConnectionProvider _idleConnectionProvider() {
  final mock = MockConnectionProvider();
  when(() => mock.status).thenReturn(ConnectionStatus.disconnected);
  when(() => mock.isReconnecting).thenReturn(false);
  when(() => mock.isConnected).thenReturn(false);
  when(() => mock.isDbConnected).thenReturn(false);
  return mock;
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

Widget _buildWidget({
  required ConfigProvider configProvider,
  required AuthProvider authProvider,
  required ConnectionProvider connectionProvider,
  WebsocketConfigFormController? formController,
  FeatureFlags? featureFlags,
  PayloadSigningConfig? payloadSigningConfig,
}) {
  final flags = featureFlags ?? FeatureFlags(InMemoryAppSettingsStore());
  final signingConfig = payloadSigningConfig ?? PayloadSigningConfig.empty();
  getIt.registerSingleton<FeatureFlags>(flags);
  getIt.registerSingleton<PayloadSigningConfig>(signingConfig);
  final form = formController ?? WebsocketConfigFormController();
  return FluentApp(
    locale: const Locale('pt'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MultiProvider(
      providers: [
        Provider<FeatureFlags>.value(value: flags),
        Provider<PayloadSigningConfig>.value(value: signingConfig),
        ChangeNotifierProvider<ConfigProvider>.value(value: configProvider),
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<ConnectionProvider>.value(
          value: connectionProvider,
        ),
        ChangeNotifierProvider<AgentOperationalReadinessProvider>.value(
          value: _idleAgentOperationalReadinessProvider(),
        ),
      ],
      child: MediaQuery(
        data: const MediaQueryData(
          textScaler: TextScaler.linear(0.72),
        ),
        child: ScaffoldPage(
          content: WebSocketConfigSection(
            formController: form,
            isSavingConfig: ValueNotifier<bool>(false),
            onSaveConfig: () async {},
          ),
        ),
      ),
    ),
  );
}

final Config _savedConfig = Config(
  id: 'cfg-1',
  serverUrl: 'https://hub.test',
  agentId: 'agent-1',
  driverName: 'SQL Server',
  odbcDriverName: 'ODBC Driver 17 for SQL Server',
  connectionString: '',
  username: '',
  databaseName: '',
  host: 'localhost',
  port: 1433,
  createdAt: DateTime.utc(2025),
  updatedAt: DateTime.utc(2025),
  authUsername: 'agent_user',
  authPassword: 'agent_pass',
);
