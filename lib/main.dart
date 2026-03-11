import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/application/use_cases/cancel_all_notifications.dart';
import 'package:plug_agente/application/use_cases/cancel_notification.dart';
import 'package:plug_agente/application/use_cases/check_odbc_driver.dart';
import 'package:plug_agente/application/use_cases/connect_to_hub.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
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
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/runtime_policy_evaluator.dart';
import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/presentation/app/app.dart';
import 'package:plug_agente/presentation/providers/auth_provider.dart';
import 'package:plug_agente/presentation/providers/config_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';
import 'package:plug_agente/presentation/providers/notification_provider.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:plug_agente/presentation/providers/runtime_mode_provider.dart';
import 'package:plug_agente/presentation/providers/websocket_log_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(isOptional: true);

  // Detect Windows version and evaluate runtime capabilities
  final probe = WindowsRuntimeProbe();
  const evaluator = RuntimePolicyEvaluator();

  final versionResult = await probe.detect();
  final capabilities = versionResult.fold(
    (versionInfo) {
      developer.log(
        'Windows version detected: $versionInfo',
        name: 'main',
        level: 800,
      );
      return evaluator.evaluate(versionInfo);
    },
    (failure) {
      developer.log(
        'Failed to detect Windows version, assuming full capabilities: $failure',
        name: 'main',
        level: 900,
      );
      return RuntimeCapabilities.full();
    },
  );

  developer.log(
    'Runtime mode: ${capabilities.mode.displayName}',
    name: 'main',
    level: 800,
  );

  if (capabilities.degradationReasons.isNotEmpty) {
    developer.log(
      'Degradation reasons: ${capabilities.degradationReasons.join(", ")}',
      name: 'main',
      level: 800,
    );
  }

  // Setup dependencies with detected capabilities
  await setupDependencies(capabilities: capabilities);

  // Handle deep links from command-line arguments
  final deepLinkService = DeepLinkService();
  final initialLink = deepLinkService.getInitialLink(args);
  final initialRoute = initialLink != null
      ? deepLinkService.deepLinkToRoute(initialLink)
      : null;

  // Initialize window manager (available in all modes)
  WindowManagerService? windowManagerService;
  if (capabilities.supportsWindowManager) {
    try {
      windowManagerService = WindowManagerService();
      final minSize = WindowConstraints.getMainWindowMinSize();
      const initialSize = Size(1200, 800);

      await windowManagerService.initialize(
        size: initialSize,
        minimumSize: minSize,
      );

      developer.log(
        'Window manager initialized',
        name: 'main',
        level: 800,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize window manager (degraded mode will continue)',
        name: 'main',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  // Initialize tray manager (only if supported)
  if (capabilities.supportsTray) {
    try {
      final trayManager = getIt<TrayManagerService>();

      await trayManager.initialize(
        onMenuAction: (action) async {
          switch (action) {
            case TrayMenuAction.show:
              await windowManagerService?.show();
            case TrayMenuAction.exit:
              try {
                trayManager.dispose();
              } on Object catch (_) {
                // Ignore errors during tray disposal
              }
              await windowManagerService?.close();
          }
        },
      );

      if (windowManagerService != null) {
        windowManagerService
          ..setMinimizeToTray(value: true)
          ..setCloseToTray(value: true);
      }

      developer.log(
        'Tray manager initialized',
        name: 'main',
        level: 800,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize tray manager (continuing without tray)',
        name: 'main',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  } else {
    developer.log(
      'Tray manager not available in degraded mode',
      name: 'main',
      level: 800,
    );
  }

  // Initialize notifications (works with both real and noop service)
  try {
    await getIt<INotificationService>().initialize();
    developer.log(
      'Notification service initialized',
      name: 'main',
      level: 800,
    );
  } on Exception catch (e, stackTrace) {
    developer.log(
      'Failed to initialize notification service',
      name: 'main',
      level: 900,
      error: e,
      stackTrace: stackTrace,
    );
  }

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
          create: (context) =>
              RuntimeModeProvider(getIt<RuntimeCapabilities>()),
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
