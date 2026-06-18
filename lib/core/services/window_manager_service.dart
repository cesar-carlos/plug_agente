import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/constants/window_timings.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:window_manager/window_manager.dart';

class WindowManagerService with WindowListener implements IWindowManagerService {
  WindowManagerService();

  final Logger _logger = Logger();
  bool _isInitialized = false;
  bool _minimizeToTray = false;
  bool _closeToTray = false;
  bool _isClosing = false;

  VoidCallback? _onMinimize;
  VoidCallback? _onClose;
  VoidCallback? _onFocus;

  Future<void> initialize({
    ui.Size? size,
    ui.Size? minimumSize,
    bool center = true,
    String? title,
    bool startMinimized = false,
  }) async {
    final windowTitle = title ?? AppConstants.appName;
    if (_isInitialized) return;

    await windowManager.ensureInitialized();

    final defaultSize = size ?? const ui.Size(1280, 800);
    final defaultMinimumSize = minimumSize ?? WindowConstraints.getMainWindowMinSize();

    final windowOptions = WindowOptions(
      size: defaultSize,
      minimumSize: defaultMinimumSize,
      center: center,
      backgroundColor: const ui.Color.fromARGB(0, 0, 0, 0),
      skipTaskbar: startMinimized,
      titleBarStyle: TitleBarStyle.normal,
      title: windowTitle,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) {
        await _ensureWindowHiddenAtStartup();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    if (startMinimized) {
      await _ensureWindowHiddenAtStartup();
    } else {
      await windowManager.setSkipTaskbar(false);
    }

    await windowManager.setMinimumSize(defaultMinimumSize);
    await windowManager.setPreventClose(false);

    windowManager.addListener(this);
    _isInitialized = true;

    _logger.i(
      'Window manager initialized - minimum size: ${defaultMinimumSize.width}x${defaultMinimumSize.height}',
    );
  }

  Future<void> _ensureWindowHiddenAtStartup() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();

    for (var attempt = 1; attempt <= WindowTimings.startupHideRetryCount; attempt++) {
      await Future<void>.delayed(WindowTimings.startupHideRetryDelay);
      final isVisible = await windowManager.isVisible();

      if (!isVisible) {
        _logger.i('Application started minimized - window hidden');
        return;
      }

      _logger.w(
        'Window visible at minimized startup (attempt $attempt), forcing hide again...',
      );
      await windowManager.hide();
      await windowManager.setSkipTaskbar(true);
      final isMinimized = await windowManager.isMinimized();
      if (!isMinimized) {
        await windowManager.minimize();
      }
    }

    final isStillVisible = await windowManager.isVisible();
    if (isStillVisible) {
      _logger.e(
        'Failed to hide window at minimized startup after '
        '${WindowTimings.startupHideRetryCount} attempts',
      );
    }
  }

  void setCallbacks({
    VoidCallback? onMinimize,
    VoidCallback? onClose,
    VoidCallback? onFocus,
  }) {
    _onMinimize = onMinimize;
    _onClose = onClose;
    _onFocus = onFocus;
  }

  @override
  void setMinimizeToTray({required bool value}) {
    _minimizeToTray = value;
    _logger.d('Minimize to tray: $value');
  }

  @override
  void setCloseToTray({required bool value}) {
    _closeToTray = value;
    _logger.d('Close to tray: $value');

    unawaited(
      _updatePreventClose(value).catchError((Object e) {
        _logger.w('Failed to configure preventClose: $e');
      }),
    );
  }

  Future<void> _updatePreventClose(bool closeToTray) async {
    try {
      if (closeToTray) {
        await windowManager.setPreventClose(true);
        _logger.d('PreventClose enabled - close will go to tray');
      } else {
        await windowManager.setPreventClose(false);
        _logger.d('PreventClose disabled - close will exit application');
      }
    } on Exception catch (e) {
      _logger.w('Failed to configure preventClose: $e');
    }
  }

  @override
  Future<void> show() async {
    try {
      _logger.i('Showing window...');

      await windowManager.setSkipTaskbar(false);
      await Future<void>.delayed(WindowTimings.showInitialDelay);

      final isMinimized = await windowManager.isMinimized();
      final isVisible = await windowManager.isVisible();

      _logger.i(
        'State before show - minimized: $isMinimized, visible: $isVisible',
      );

      if (isMinimized) {
        _logger.i('Window is minimized, restoring...');
        await windowManager.restore();
        await Future<void>.delayed(WindowTimings.showRestoreDelay);
      }

      _logger.i('Calling show()...');
      await windowManager.show();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final isVisibleAfterShow = await windowManager.isVisible();
      _logger.i('Visible after show(): $isVisibleAfterShow');

      if (!isVisibleAfterShow) {
        _logger.w(
          'Window not visible after show(), trying restore...',
        );
        await windowManager.restore();
        await Future<void>.delayed(WindowTimings.showRestoreDelay);
        await windowManager.show();
        await Future<void>.delayed(WindowTimings.showRestoreDelay);
      }

      _logger.i('Focusing window...');
      await windowManager.focus();
      await Future<void>.delayed(WindowTimings.showInitialDelay);

      final finalIsVisible = await windowManager.isVisible();
      final finalIsMinimized = await windowManager.isMinimized();
      _logger.i(
        'Window shown - visible: $finalIsVisible, minimized: $finalIsMinimized',
      );

      if (!finalIsVisible) {
        _logger.e(
          'Window still not visible after all show attempts',
        );
        await windowManager.restore();
        await Future<void>.delayed(WindowTimings.showFinalDelay);
        await windowManager.show();
        await windowManager.focus();
      }
    } on Exception catch (e, stackTrace) {
      _logger.e('Failed to show window', error: e, stackTrace: stackTrace);
      try {
        _logger.i('Trying alternative show path...');
        await windowManager.restore();
        await Future<void>.delayed(WindowTimings.showRestoreDelay);
        await windowManager.show();
        await windowManager.focus();
      } on Exception catch (e2) {
        _logger.e('Critical error showing window', error: e2);
        rethrow;
      }
    }
  }

  Future<void> restore() async {
    await windowManager.restore();
    await Future<void>.delayed(WindowTimings.showRestoreDelay);
    await show();
  }

  Future<void> hide() async {
    await windowManager.hide();
  }

  Future<void> minimize() async {
    await windowManager.minimize();
  }

  Future<void> maximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Future<void> close() async {
    try {
      _logger.i('Closing application...');

      // Shutdown all resources before closing window
      await shutdownApp();

      _isClosing = true;
      _closeToTray = false;
      await windowManager.setPreventClose(false);
      await windowManager.close();

      _logger.i('Application closed');
    } on Exception catch (e, stackTrace) {
      _logger.e('Failed to close application', error: e, stackTrace: stackTrace);
      exit(0);
    }
  }

  Future<void> allowQuitForUpdate() async {
    _isClosing = true;
    _closeToTray = false;
    await windowManager.setPreventClose(false);
  }

  Future<void> setTitle(String title) async {
    await windowManager.setTitle(title);
  }

  Future<bool> isVisible() async {
    return windowManager.isVisible();
  }

  Future<bool> isMinimized() async {
    return windowManager.isMinimized();
  }

  Future<bool> isFocused() async {
    return windowManager.isFocused();
  }

  // WindowListener callbacks
  @override
  void onWindowMinimize() {
    if (_minimizeToTray) {
      unawaited(
        _hideToTray().catchError((Object e) {
          _logger.e('Failed to hide window on minimize', error: e);
        }),
      );
    }
    _onMinimize?.call();
  }

  Future<void> _hideToTray() async {
    await hide();
    await windowManager.setSkipTaskbar(true);
  }

  @override
  Future<void> onWindowClose() async {
    if (_isClosing) {
      _logger.d('Intentional close - allowing');
      return;
    }

    _logger.i('Window close attempt - closeToTray: $_closeToTray');

    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose && !_closeToTray) {
        _logger.d('Close prevented by another reason - ignoring event');
        return;
      }
    } on Exception catch (e) {
      _logger.w('Failed to check preventClose: $e');
    }

    if (_closeToTray) {
      try {
        await windowManager.setPreventClose(true);
        await hide();
        await windowManager.setSkipTaskbar(true);
        _logger.i('Window hidden to tray (close prevented)');
      } on Exception catch (e) {
        _logger.e('Failed to hide window to tray', error: e);
        try {
          await hide();
          await windowManager.setSkipTaskbar(true);
        } on Exception catch (e2) {
          _logger.e('Critical error hiding window', error: e2);
        }
      }
    } else {
      try {
        _logger.i('Close allowed - exiting application');
        _onClose?.call();
        await close();
      } on Exception catch (e) {
        _logger.e('Failed to configure preventClose for close', error: e);
        _onClose?.call();
        await close();
      }
    }
  }

  @override
  void onWindowFocus() {
    _onFocus?.call();
  }

  @override
  void onWindowBlur() {}

  @override
  void onWindowMaximize() {}

  @override
  void onWindowUnmaximize() {}

  @override
  void onWindowRestore() {}

  @override
  void onWindowResize() {}

  @override
  void onWindowMove() {}

  @override
  void onWindowEnterFullScreen() {}

  @override
  void onWindowLeaveFullScreen() {}

  @override
  void onWindowEvent(String eventName) {}

  void dispose() {
    windowManager.removeListener(this);
  }
}
