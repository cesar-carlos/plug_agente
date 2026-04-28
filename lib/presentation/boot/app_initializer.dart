import 'dart:async';
import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/deep_link_service.dart';
import 'package:plug_agente/core/runtime/app_uptime.dart';
import 'package:plug_agente/core/runtime/i_windows_runtime_probe.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_mode.dart';
import 'package:plug_agente/core/runtime/runtime_policy_evaluator.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/repositories/i_notification_service.dart';
import 'package:plug_agente/infrastructure/pool/odbc_connection_pool.dart';
import 'package:plug_agente/presentation/boot/app_bootstrap_data.dart';

typedef StartupWindowPreferences = ({
  bool startMinimized,
  bool minimizeToTray,
  bool closeToTray,
});

@visibleForTesting
StartupWindowPreferences resolveStartupWindowPreferences(
  IAppSettingsStore settingsStore, {
  bool canStartMinimized = true,
}) {
  return (
    startMinimized: canStartMinimized && (settingsStore.getBool('settings.start_minimized') ?? false),
    minimizeToTray: settingsStore.getBool('settings.minimize_to_tray') ?? true,
    closeToTray: settingsStore.getBool('settings.close_to_tray') ?? true,
  );
}

class AppInitializer {
  const AppInitializer({required this.runtimeProbe});

  final IWindowsRuntimeProbe runtimeProbe;

  Future<AppBootstrapData> initialize(List<String> args) async {
    AppUptime.markStarted();
    await dotenv.load(isOptional: true);

    final capabilities = await _resolveRuntimeCapabilities();
    await setupDependencies(capabilities: capabilities);

    // Warm up ODBC connection pool if connection string is configured
    await _warmUpConnectionPool();

    final initialRoute = _resolveInitialRoute(args);
    await _initializeDesktopFeatures(capabilities);

    return AppBootstrapData(
      capabilities: capabilities,
      initialRoute: initialRoute,
    );
  }

  Future<RuntimeCapabilities> _resolveRuntimeCapabilities() async {
    final probe = runtimeProbe;
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
    return initialLink != null ? deepLinkService.deepLinkToRoute(initialLink) : null;
  }

  Future<void> _warmUpConnectionPool() async {
    try {
      final config = getIt<IAgentConfigRepository>();
      final configResult = await config.getCurrentConfig();
      
      await configResult.fold(
        (agentConfig) async {
          if (agentConfig.connectionString.isEmpty) {
            developer.log(
              'Skipping pool warm-up: no connection string configured',
              name: 'app_initializer',
              level: 500,
            );
            return;
          }

          final pool = getIt<IConnectionPool>();
          if (pool is OdbcConnectionPool) {
            await pool.warmUp(agentConfig.connectionString);
          }
        },
        (failure) {
          developer.log(
            'Skipping pool warm-up: config not available',
            name: 'app_initializer',
            level: 500,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Pool warm-up failed (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initializeDesktopFeatures(
    RuntimeCapabilities capabilities,
  ) async {
    WindowManagerService? windowManagerService;

    if (capabilities.supportsWindowManager) {
      windowManagerService = await _initializeWindowManager(capabilities);
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
    await _initializeAutoUpdate(capabilities);
  }

  Future<void> _initializeAutoUpdate(
    RuntimeCapabilities capabilities,
  ) async {
    if (!capabilities.supportsAutoUpdate) {
      developer.log(
        'Auto-update skipped: not supported in current runtime mode',
        name: 'app_initializer',
        level: 800,
      );
      return;
    }

    try {
      final orchestrator = getIt<IAutoUpdateOrchestrator>();
      await orchestrator.initialize();
      if (orchestrator.isAvailable) {
        unawaited(orchestrator.checkInBackground());
        developer.log(
          'Auto-update initialized and initial background check triggered',
          name: 'app_initializer',
          level: 800,
        );
      }
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize auto-update (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<WindowManagerService?> _initializeWindowManager(
    RuntimeCapabilities capabilities,
  ) async {
    try {
      final windowManagerService = WindowManagerService();
      final minSize = WindowConstraints.getMainWindowMinSize();
      const initialSize = Size(1200, 800);

      final prefs = getIt<IAppSettingsStore>();
      final preferences = resolveStartupWindowPreferences(
        prefs,
        canStartMinimized: capabilities.supportsTray,
      );

      await windowManagerService.initialize(
        size: initialSize,
        minimumSize: minSize,
        startMinimized: preferences.startMinimized,
      );

      getIt.registerSingleton<WindowManagerService>(windowManagerService);
      getIt.registerSingleton<IWindowManagerService>(windowManagerService);

      developer.log(
        'Window manager initialized '
        '(startMinimized: ${preferences.startMinimized})',
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
        final prefs = getIt<IAppSettingsStore>();
        final preferences = resolveStartupWindowPreferences(prefs);

        windowManagerService
          ..setMinimizeToTray(value: preferences.minimizeToTray)
          ..setCloseToTray(value: preferences.closeToTray);

        developer.log(
          'Tray behaviors configured '
          '(minimize: ${preferences.minimizeToTray}, '
          'close: ${preferences.closeToTray})',
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
      final result = await getIt<INotificationService>().initialize();
      result.fold(
        (_) {
          developer.log(
            'Notification service initialized',
            name: 'app_initializer',
            level: 800,
          );
        },
        (failure) {
          developer.log(
            'Failed to initialize notification service (continuing without)',
            name: 'app_initializer',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize notification service (continuing without)',
        name: 'app_initializer',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
