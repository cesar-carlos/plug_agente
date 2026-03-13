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
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
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

class _ProviderInitializer extends StatelessWidget {
  const _ProviderInitializer({
    required this.capabilities,
    this.initialRoute,
  });

  final RuntimeCapabilities capabilities;
  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    final connectionProvider = context.read<ConnectionProvider>();
    final authProvider = context.read<AuthProvider>();
    final configProvider = context.read<ConfigProvider>();

    connectionProvider.setAuthProvider(authProvider);
    connectionProvider.setConfigProvider(configProvider);

    return PlugAgentApp(
      initialRoute: initialRoute,
      capabilities: capabilities,
    );
  }
}
