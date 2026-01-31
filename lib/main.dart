import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/load_agent_config.dart';
import 'package:plug_agente/application/use_cases/login_user.dart';
import 'package:plug_agente/application/use_cases/refresh_auth_token.dart';
import 'package:plug_agente/application/use_cases/save_agent_config.dart';
import 'package:plug_agente/application/use_cases/save_auth_token.dart';
import 'package:plug_agente/application/use_cases/schedule_notification.dart';
import 'package:plug_agente/application/use_cases/send_notification.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/presentation/app/app.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/presentation/providers/notification_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(isOptional: true);
  await setupDependencies();

  // Handle deep links from command-line arguments
  final deepLinkService = DeepLinkService();
  final initialLink = deepLinkService.getInitialLink(args);
  final initialRoute = initialLink != null
      ? deepLinkService.deepLinkToRoute(initialLink)
      : null;

  final windowManagerService = WindowManagerService();
  final minSize = WindowConstraints.getMainWindowMinSize();
  const initialSize = Size(1200, 800);

  await windowManagerService.initialize(
    size: initialSize,
    minimumSize: minSize,
  );

  final trayManager = getIt<TrayManagerService>();

  await trayManager.initialize(
    onMenuAction: (action) async {
      switch (action) {
        case TrayMenuAction.show:
          await windowManagerService.show();
        case TrayMenuAction.exit:
          try {
            trayManager.dispose();
          } on Object catch (_) {
            // Ignore errors during tray disposal
          }

          await windowManagerService.close();
      }
    },
  );

  windowManagerService.setMinimizeToTray(value: true);
  windowManagerService.setCloseToTray(value: true);

  await getIt<INotificationService>().initialize();

  runApp(MyApp(initialRoute: initialRoute));
}

class MyApp extends StatelessWidget {
  const MyApp({
    this.initialRoute,
    super.key,
  });

  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
          ),
        ),
        ChangeNotifierProvider(create: (context) => WebSocketLogProvider()),
      ],
      child: _ProviderInitializer(initialRoute: initialRoute),
    );
  }
}

class _ProviderInitializer extends StatelessWidget {
  const _ProviderInitializer({
    this.initialRoute,
  });

  final String? initialRoute;

  @override
  Widget build(BuildContext context) {
    final connectionProvider = context.read<ConnectionProvider>();
    final authProvider = context.read<AuthProvider>();
    final configProvider = context.read<ConfigProvider>();

    connectionProvider.setAuthProvider(authProvider);
    connectionProvider.setConfigProvider(configProvider);

    return PlugAgentApp(initialRoute: initialRoute);
  }
}
