import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:uuid/uuid.dart';

import 'core/di/service_locator.dart';
import 'core/constants/window_constraints.dart';
import 'core/services/tray_manager_service.dart';
import 'core/services/window_manager_service.dart';
import 'domain/repositories/i_notification_service.dart';
import 'application/use_cases/connect_to_hub.dart';
import 'application/use_cases/test_db_connection.dart';
import 'application/use_cases/execute_playground_query.dart';
import 'application/use_cases/save_agent_config.dart';
import 'application/use_cases/load_agent_config.dart';
import 'application/use_cases/cancel_all_notifications.dart';
import 'application/use_cases/cancel_notification.dart';
import 'application/use_cases/send_notification.dart';
import 'application/use_cases/schedule_notification.dart';
import 'application/services/config_service.dart';
import 'presentation/providers/connection_provider.dart';
import 'presentation/providers/config_provider.dart';
import 'presentation/providers/notification_provider.dart';
import 'presentation/providers/playground_provider.dart';
import 'presentation/providers/websocket_log_provider.dart';
import 'presentation/providers/auth_provider.dart';
import 'application/use_cases/login_user.dart';
import 'application/use_cases/refresh_auth_token.dart';
import 'application/use_cases/save_auth_token.dart';
import 'presentation/app/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env', isOptional: true);
  await setupDependencies();

  final windowManagerService = WindowManagerService();
  final minSize = WindowConstraints.getMainWindowMinSize();
  const initialSize = Size(1200, 800);

  await windowManagerService.initialize(size: initialSize, minimumSize: minSize, center: true, startMinimized: false);

  final trayManager = getIt<TrayManagerService>();

  await trayManager.initialize(
    onMenuAction: (action) async {
      switch (action) {
        case TrayMenuAction.show:
          await windowManagerService.show();
          break;
        case TrayMenuAction.exit:
          try {
            trayManager.dispose();
          } catch (e) {}

          await windowManagerService.close();
          break;
      }
    },
  );

  windowManagerService.setMinimizeToTray(true);
  windowManagerService.setCloseToTray(true);

  await getIt<INotificationService>().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) =>
              ConfigProvider(getIt<SaveAgentConfig>(), getIt<LoadAgentConfig>(), getIt<ConfigService>(), getIt<Uuid>()),
        ),
        ChangeNotifierProvider(
          create: (context) => AuthProvider(getIt<LoginUser>(), getIt<RefreshAuthToken>(), getIt<SaveAuthToken>()),
        ),
        ChangeNotifierProvider(
          create: (context) => ConnectionProvider(getIt<ConnectToHub>(), getIt<TestDbConnection>()),
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
          create: (context) => PlaygroundProvider(getIt<ExecutePlaygroundQuery>(), getIt<TestDbConnection>()),
        ),
        ChangeNotifierProvider(create: (context) => WebSocketLogProvider()),
      ],
      child: const _ProviderInitializer(),
    );
  }
}

class _ProviderInitializer extends StatelessWidget {
  const _ProviderInitializer();

  @override
  Widget build(BuildContext context) {
    final connectionProvider = context.read<ConnectionProvider>();
    final authProvider = context.read<AuthProvider>();
    final configProvider = context.read<ConfigProvider>();

    connectionProvider.setAuthProvider(authProvider);
    connectionProvider.setConfigProvider(configProvider);

    return const PlugAgentApp();
  }
}
