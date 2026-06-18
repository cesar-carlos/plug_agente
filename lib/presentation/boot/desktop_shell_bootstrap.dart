import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/policies/app_preferences_policy.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/presentation/boot/desktop_shell_bootstrap_dependencies.dart';

export 'package:plug_agente/presentation/boot/desktop_shell_bootstrap_dependencies.dart'
    show DesktopShellBootstrapDependencies;

typedef StartupWindowPreferences = ({
  bool startMinimized,
  bool minimizeToTray,
  bool closeToTray,
});

typedef NativeWindowVisibilityFallback = Future<void> Function();

const MethodChannel _runtimeChannel = MethodChannel('plug_agente/runtime');

@visibleForTesting
Future<void> showNativeRuntimeWindow() async {
  await _runtimeChannel.invokeMethod<bool>('showWindow');
}

@visibleForTesting
StartupWindowPreferences resolveStartupWindowPreferences(
  IAppSettingsStore settingsStore, {
  bool canStartMinimized = true,
  bool isAutostartLaunch = false,
}) {
  return (
    startMinimized: AppPreferencesPolicy.shouldStartMinimizedAtLaunch(
      supportsTray: canStartMinimized,
      isAutostartLaunch: isAutostartLaunch,
      startMinimizedPreference: settingsStore.getBool(AppSettingsKeys.startMinimized) ?? false,
    ),
    minimizeToTray: settingsStore.getBool(AppSettingsKeys.minimizeToTray) ?? true,
    closeToTray: settingsStore.getBool(AppSettingsKeys.closeToTray) ?? true,
  );
}

class DesktopShellBootstrap {
  DesktopShellBootstrap({
    required this.isAutostartLaunch,
    required DesktopShellBootstrapDependencies dependencies,
    NativeWindowVisibilityFallback? nativeWindowVisibilityFallback,
  }) : _dependencies = dependencies,
       _nativeWindowVisibilityFallback = nativeWindowVisibilityFallback ?? showNativeRuntimeWindow;

  final bool isAutostartLaunch;
  final DesktopShellBootstrapDependencies _dependencies;
  final NativeWindowVisibilityFallback _nativeWindowVisibilityFallback;

  Future<void> initialize(RuntimeCapabilities capabilities) async {
    WindowManagerService? windowManagerService;

    if (capabilities.supportsWindowManager) {
      windowManagerService = await _initializeWindowManager(capabilities);
    } else {
      await _restoreNativeWindowWhenWindowManagerUnavailable();
    }

    if (capabilities.supportsTray && windowManagerService != null) {
      await _initializeTray(windowManagerService);
    } else if (capabilities.supportsTray) {
      developer.log(
        'Tray manager skipped because window manager is unavailable',
        name: 'desktop_shell_bootstrap',
        level: 800,
      );
    } else {
      developer.log(
        'Tray manager not available in degraded mode',
        name: 'desktop_shell_bootstrap',
        level: 800,
      );
    }

    await _initializeNotifications();
  }

  Future<WindowManagerService?> _initializeWindowManager(
    RuntimeCapabilities capabilities,
  ) async {
    try {
      final windowManagerService = _dependencies.resolveWindowManager ?? WindowManagerService();
      final minSize = WindowConstraints.getMainWindowMinSize();
      const initialSize = Size(1200, 800);

      final prefs = _dependencies.settingsStore;
      final preferences = resolveStartupWindowPreferences(
        prefs,
        canStartMinimized: capabilities.supportsTray,
        isAutostartLaunch: isAutostartLaunch,
      );

      await windowManagerService.initialize(
        size: initialSize,
        minimumSize: minSize,
        startMinimized: preferences.startMinimized,
      );

      developer.log(
        'Window manager initialized '
        '(startMinimized: ${preferences.startMinimized})',
        name: 'desktop_shell_bootstrap',
        level: 800,
      );
      return windowManagerService;
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize window manager (degraded mode will continue)',
        name: 'desktop_shell_bootstrap',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      await _restoreNativeWindowAfterWindowManagerFailure();
      return null;
    }
  }

  Future<void> _restoreNativeWindowAfterWindowManagerFailure() async {
    if (!isAutostartLaunch) {
      return;
    }

    try {
      await _nativeWindowVisibilityFallback();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to restore native window after window manager initialization failure',
        name: 'desktop_shell_bootstrap',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _restoreNativeWindowWhenWindowManagerUnavailable() async {
    if (!isAutostartLaunch) {
      return;
    }

    try {
      await _nativeWindowVisibilityFallback();
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to restore native window when window manager is unavailable',
        name: 'desktop_shell_bootstrap',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initializeTray(
    WindowManagerService windowManagerService,
  ) async {
    try {
      final trayService = _dependencies.trayService;
      await trayService.initialize(
        onMenuAction: (action) async {
          switch (action) {
            case TrayMenuAction.show:
              await windowManagerService.show();
            case TrayMenuAction.exit:
              trayService.dispose();
              await windowManagerService.close();
          }
        },
      );

      final prefs = _dependencies.settingsStore;
      final preferences = resolveStartupWindowPreferences(prefs);

      windowManagerService
        ..setMinimizeToTray(value: preferences.minimizeToTray)
        ..setCloseToTray(value: preferences.closeToTray);

      developer.log(
        'Tray behaviors configured '
        '(minimize: ${preferences.minimizeToTray}, '
        'close: ${preferences.closeToTray})',
        name: 'desktop_shell_bootstrap',
        level: 800,
      );

      developer.log(
        'Tray manager initialized',
        name: 'desktop_shell_bootstrap',
        level: 800,
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize tray manager (continuing without tray)',
        name: 'desktop_shell_bootstrap',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
      await _restoreWindowAfterTrayFailure(windowManagerService);
    }
  }

  Future<void> _restoreWindowAfterTrayFailure(
    WindowManagerService windowManagerService,
  ) async {
    try {
      if (!await windowManagerService.isVisible()) {
        await windowManagerService.show();
      }
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to restore window after tray initialization failure',
        name: 'desktop_shell_bootstrap',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _initializeNotifications() async {
    try {
      final result = await _dependencies.notificationService.initialize();
      result.fold(
        (_) {
          developer.log(
            'Notification service initialized',
            name: 'desktop_shell_bootstrap',
            level: 800,
          );
        },
        (failure) {
          developer.log(
            'Failed to initialize notification service (continuing without)',
            name: 'desktop_shell_bootstrap',
            level: 900,
            error: failure,
          );
        },
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Failed to initialize notification service (continuing without)',
        name: 'desktop_shell_bootstrap',
        level: 900,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
