import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/create_client_token.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/list_client_tokens.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/utils/url_utils.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/auth_credentials.dart';
import 'package:plug_agente/presentation/app/app.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/presentation/providers/notification_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/presentation/providers/runtime_mode_provider.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AppRoot extends StatelessWidget {
  const AppRoot({
    required this.capabilities,
    this.initialRoute,
    super.key,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) =>
              RuntimeModeProvider(getIt<RuntimeCapabilities>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ThemeProvider(getIt<SharedPreferences>()),
        ),
        ChangeNotifierProvider(
          create: (context) => SystemSettingsProvider(
            getIt<SharedPreferences>(),
            windowManagerService: getIt.isRegistered<WindowManagerService>()
                ? getIt<WindowManagerService>()
                : null,
            startupService: getIt.isRegistered<IStartupService>()
                ? getIt<IStartupService>()
                : null,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ConfigProvider(
            getIt<SaveAgentConfig>(),
            getIt<LoadAgentConfig>(),
            getIt<ConfigService>(),
            getIt<Uuid>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthProvider(
            getIt<LoginUser>(),
            getIt<RefreshAuthToken>(),
            getIt<SaveAuthToken>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ConnectionProvider(
            getIt<ConnectToHub>(),
            getIt<TestDbConnection>(),
            getIt<CheckOdbcDriver>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => ClientTokenProvider(
            getIt<CreateClientToken>(),
            getIt<UpdateClientToken>(),
            getIt<ListClientTokens>(),
            getIt<RevokeClientToken>(),
            getIt<DeleteClientToken>(),
            tokenAuditStore: getIt<ITokenAuditStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => NotificationProvider(
            getIt<SendNotification>(),
            getIt<ScheduleNotification>(),
            getIt<CancelNotification>(),
            getIt<CancelAllNotifications>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => PlaygroundProvider(
            getIt<ExecutePlaygroundQuery>(),
            getIt<TestDbConnection>(),
            getIt<ExecuteStreamingQuery>(),
          ),
        ),
        ChangeNotifierProvider(create: (context) => WebSocketLogProvider()),
      ],
      child: _ProviderInitializer(
        initialRoute: initialRoute,
        capabilities: capabilities,
      ),
    );
  }
}

class _ProviderInitializer extends StatefulWidget {
  const _ProviderInitializer({
    required this.capabilities,
    this.initialRoute,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;

  @override
  State<_ProviderInitializer> createState() => _ProviderInitializerState();
}

class _ProviderInitializerState extends State<_ProviderInitializer> {
  static const String _defaultServerUrl = 'https://api.example.com';

  ConnectionProvider? _connectionProvider;
  AuthProvider? _authProvider;
  ConfigProvider? _configProvider;
  bool _startupFlowHandled = false;
  bool _startupFlowRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProviders();
    });
  }

  @override
  void dispose() {
    _configProvider?.removeListener(_onConfigStateChanged);
    super.dispose();
  }

  void _initializeProviders() {
    if (!mounted) {
      return;
    }
    final connectionProvider = context.read<ConnectionProvider>();
    final authProvider = context.read<AuthProvider>();
    final configProvider = context.read<ConfigProvider>();

    _connectionProvider = connectionProvider;
    _authProvider = authProvider;
    _configProvider = configProvider;

    connectionProvider.setAuthProvider(authProvider);
    connectionProvider.setConfigProvider(configProvider);

    configProvider.removeListener(_onConfigStateChanged);
    configProvider.addListener(_onConfigStateChanged);

    _attemptStartupLoginAndConnect();
  }

  void _onConfigStateChanged() {
    _attemptStartupLoginAndConnect();
  }

  Future<void> _attemptStartupLoginAndConnect() async {
    if (!mounted || _startupFlowHandled || _startupFlowRunning) {
      return;
    }

    final configProvider = _configProvider;
    final connectionProvider = _connectionProvider;
    final authProvider = _authProvider;
    if (configProvider == null ||
        connectionProvider == null ||
        authProvider == null) {
      return;
    }

    if (configProvider.isLoading) {
      return;
    }
    if (connectionProvider.isConnected ||
        connectionProvider.status == ConnectionStatus.connecting ||
        connectionProvider.status == ConnectionStatus.reconnecting) {
      _markStartupFlowHandled();
      return;
    }

    final config = configProvider.currentConfig;
    if (config == null) {
      _markStartupFlowHandled();
      return;
    }

    final startupContext = _buildStartupContext(config);
    if (startupContext == null) {
      _markStartupFlowHandled();
      return;
    }

    _startupFlowHandled = true;
    _startupFlowRunning = true;
    try {
      var authToken = startupContext.authToken;
      if (startupContext.credentials != null) {
        await authProvider.login(
          startupContext.serverUrl,
          startupContext.credentials!,
        );
        final refreshedToken = authProvider.currentToken?.token.trim();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          authToken = refreshedToken;
        }
      }

      await connectionProvider.connect(
        startupContext.serverUrl,
        startupContext.agentId,
        authToken: authToken,
      );
    } finally {
      _startupFlowRunning = false;
      _configProvider?.removeListener(_onConfigStateChanged);
    }
  }

  _StartupContext? _buildStartupContext(Config config) {
    final serverUrl = normalizeServerUrl(config.serverUrl);
    final agentId = config.agentId.trim();

    if (serverUrl.isEmpty ||
        serverUrl.toLowerCase() == _defaultServerUrl ||
        agentId.isEmpty) {
      return null;
    }

    final authToken = config.authToken?.trim();
    final hasAuthToken = authToken != null && authToken.isNotEmpty;
    final authUsername = config.authUsername?.trim();
    final authPassword = config.authPassword?.trim();
    final hasAuthCredentials =
        authUsername != null &&
        authUsername.isNotEmpty &&
        authPassword != null &&
        authPassword.isNotEmpty;

    if (!hasAuthToken && !hasAuthCredentials) {
      return null;
    }

    return _StartupContext(
      serverUrl: serverUrl,
      agentId: agentId,
      authToken: hasAuthToken ? authToken : null,
      credentials: hasAuthCredentials
          ? AuthCredentials(
              username: authUsername,
              password: authPassword,
              agentId: agentId,
            )
          : null,
    );
  }

  void _markStartupFlowHandled() {
    _startupFlowHandled = true;
    _configProvider?.removeListener(_onConfigStateChanged);
    AppLogger.debug('Startup auth/socket auto-flow skipped');
  }

  @override
  Widget build(BuildContext context) {
    return PlugAgentApp(
      initialRoute: widget.initialRoute,
      capabilities: widget.capabilities,
    );
  }
}

class _StartupContext {
  const _StartupContext({
    required this.serverUrl,
    required this.agentId,
    this.authToken,
    this.credentials,
  });

  final String serverUrl;
  final String agentId;
  final String? authToken;
  final AuthCredentials? credentials;
}
