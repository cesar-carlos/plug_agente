import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/runtime_policy_evaluator.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/infrastructure/runtime/windows_runtime_probe.dart';
import 'package:plug_agente/presentation/boot/app_bootstrap_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppInitializer {
  const AppInitializer();

  Future<AppBootstrapData> initialize(List<String> args) async {
    await dotenv.load(isOptional: true);

    final capabilities = await _resolveRuntimeCapabilities();
    await setupDependencies(capabilities: capabilities);

    final initialRoute = _resolveInitialRoute(args);
    await _initializeDesktopFeatures(capabilities);

    return AppBootstrapData(
      capabilities: capabilities,
      initialRoute: initialRoute,
    );
  }

  Future<RuntimeCapabilities> _resolveRuntimeCapabilities() async {
    final probe = WindowsRuntimeProbe();
    const evaluator = RuntimePolicyEvaluator();

    final versionResult = await probe.detect();
    final capabilities = versionResult.fold(
      (versionInfo) {
        developer.log(
          'Windows version detected: $versionInfo',
          name: 'app_initializer',
          level: 800,
        );
        return evaluator.evaluate(versionInfo);
      },
      (failure) {
        developer.log(
          'Failed to detect Windows version, using degraded safe mode: $failure',
          name: 'app_initializer',
          level: 900,
        );
        return RuntimeCapabilities.degraded(
          reasons: <String>[
            'Falha ao detectar versão do Windows com confiança',
            'Fallback seguro aplicado para evitar crashes de plugins desktop',
          ],
        );
      },
    );

    developer.log(
      'Runtime mode: ${capabilities.mode.displayName}',
      name: 'app_initializer',
      level: 800,
    );

    if (capabilities.degradationReasons.isNotEmpty) {
      developer.log(
        'Degradation reasons: ${capabilities.degradationReasons.join(", ")}',
        name: 'app_initializer',
        level: 800,
      );
    }

    return capabilities;
  }

  String? _resolveInitialRoute(List<String> args) {
    final deepLinkService = DeepLinkService();
    final initialLink = deepLinkService.getInitialLink(args);
    return initialLink != null
        ? deepLinkService.deepLinkToRoute(initialLink)
        : null;
  }

  Future<void> _initializeDesktopFeatures(
    RuntimeCapabilities capabilities,
  ) async {
    WindowManagerService? windowManagerService;

    if (capabilities.supportsWindowManager) {
      windowManagerService = await _initializeWindowManager();
    }

    if (capabilities.supportsTray) {
      await _initializeTray(windowManagerService);
    } else {
      developer.log(
        'Tray manager not available in degraded mode',
        name: 'app_initializer',
        level: 800,
      );
    }

    await _initializeNotifications();
  }

  Future<WindowManagerService?> _initializeWindowManager() async {
    try {
      final windowManagerService = WindowManagerService();
      final minSize = WindowConstraints.getMainWindowMinSize();
      const initialSize = Size(1200, 800);

      final prefs = getIt<SharedPreferences>();
      final startMinimized = prefs.getBool('settings.start_minimized') ?? false;

      await windowManagerService.initialize(
        size: initialSize,
        minimumSize: minSize,
        startMinimized: startMinimized,
      );

      getIt.registerSingleton<WindowManagerService>(windowManagerService);

      developer.log(
        'Window manager initialized (startMinimized: $startMinimized)',
        name: 'app_initializer',
        level: 800,
      );
      return windowManagerService;
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize window manager (degraded mode will continue)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _initializeTray(
    WindowManagerService? windowManagerService,
  ) async {
    try {
      final trayService = getIt<ITrayService>();
      await trayService.initialize(
        onMenuAction: (action) async {
          switch (action) {
            case TrayMenuAction.show:
              await windowManagerService?.show();
            case TrayMenuAction.exit:
              trayService.dispose();
              await windowManagerService?.close();
          }
        },
      );

      if (windowManagerService != null) {
        final prefs = getIt<SharedPreferences>();
        final minimizeToTray =
            prefs.getBool('settings.minimize_to_tray') ?? true;
        final closeToTray = prefs.getBool('settings.close_to_tray') ?? true;

        windowManagerService
          ..setMinimizeToTray(value: minimizeToTray)
          ..setCloseToTray(value: closeToTray);

        developer.log(
          'Tray behaviors configured (minimize: $minimizeToTray, close: $closeToTray)',
          name: 'app_initializer',
          level: 800,
        );
      }

      developer.log(
        'Tray manager initialized',
        name: 'app_initializer',
        level: 800,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize tray manager (continuing without tray)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      await getIt<INotificationService>().initialize();
      developer.log(
        'Notification service initialized',
        name: 'app_initializer',
        level: 800,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize notification service',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
