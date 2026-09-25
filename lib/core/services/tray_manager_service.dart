// tray_manager 0.7 moved the 0.5 API to legacy.dart. The native TrayIcon
// API is a separate rewrite; this bridge stays until that migration.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plug_agente/core/constants/window_timings.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:tray_manager/legacy.dart';

class TrayManagerService with TrayListener implements ITrayService {
  factory TrayManagerService() => _instance;
  TrayManagerService._();
  static final TrayManagerService _instance = TrayManagerService._();

  final Logger _logger = Logger();
  TrayMenuActionHandler? _onMenuAction;
  bool _isInitialized = false;
  bool _interactionsEnabled = false;
  String? _cachedIconPath;
  String _showWindowLabel = 'Open Plug Database';
  String _exitLabel = 'Exit';
  TrayAvailability _availability = TrayAvailability.initializing;
  Future<void>? _disposeFuture;

  @override
  TrayAvailability get availability => _availability;

  @override
  bool get isReady => _availability == TrayAvailability.ready;

  @override
  Future<void> initialize({
    TrayMenuActionHandler? onMenuAction,
    String showWindowLabel = 'Open Plug Database',
    String exitLabel = 'Exit',
  }) async {
    if (_isInitialized) return;

    final pendingDispose = _disposeFuture;
    if (pendingDispose != null) {
      await pendingDispose;
      _disposeFuture = null;
    }

    _availability = TrayAvailability.initializing;
    _onMenuAction = onMenuAction;
    _showWindowLabel = showWindowLabel;
    _exitLabel = exitLabel;
    trayManager.addListener(this);

    try {
      final iconPath = await _getTrayIconPath();
      final iconFile = File(iconPath);

      if (iconFile.existsSync()) {
        await trayManager.setIcon(iconFile.absolute.path);
      } else {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
      }
    } on Object catch (e, stackTrace) {
      _logger.e(
        'Failed to set tray icon',
        error: e,
        stackTrace: stackTrace,
      );
      try {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
      } on Object catch (e2, stackTrace) {
        _logger.e('Critical error setting tray icon', error: e2);
        await _rollbackFailedInitialization();
        _availability = TrayAvailability.failed;
        Error.throwWithStackTrace(e2, stackTrace);
      }
    }

    try {
      await trayManager.setToolTip('Plug Database');
      await Future<void>.delayed(WindowTimings.trayInitDelay);

      await _updateMenu();
      await Future<void>.delayed(WindowTimings.trayInitDelay);

      _isInitialized = true;
      _availability = TrayAvailability.ready;
      _enableInteractionsAfterWarmup();
      _logger.i('TrayManager initialized');
    } on Object catch (e, stackTrace) {
      _logger.e(
        'Error during TrayManager initialization',
        error: e,
        stackTrace: stackTrace,
      );
      await _rollbackFailedInitialization();
      _availability = TrayAvailability.failed;
      rethrow;
    }
  }

  void _enableInteractionsAfterWarmup() {
    unawaited(
      Future<void>.delayed(WindowTimings.trayInteractionWarmupDelay, () {
        if (_availability == TrayAvailability.ready) {
          _interactionsEnabled = true;
        }
      }),
    );
  }

  Future<void> _rollbackFailedInitialization() async {
    await _disposeTray();
  }

  Future<void> _disposeTray() {
    final existingDispose = _disposeFuture;
    if (existingDispose != null) {
      return existingDispose;
    }

    _isInitialized = false;
    _interactionsEnabled = false;
    _availability = TrayAvailability.failed;
    _onMenuAction = null;
    trayManager.removeListener(this);

    final disposeFuture = _destroyTray();
    _disposeFuture = disposeFuture;
    return disposeFuture;
  }

  Future<void> _destroyTray() async {
    try {
      await trayManager.destroy();
    } on Object catch (error, stackTrace) {
      _logger.w(
        'Failed to destroy TrayManager after initialization error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String> _getTrayIconPath() async {
    if (Platform.isWindows) {
      if (_cachedIconPath != null) {
        final cachedFile = File(_cachedIconPath!);
        if (cachedFile.existsSync()) {
          return _cachedIconPath!;
        }
      }

      final executablePath = Platform.resolvedExecutable;
      final executableDir = Directory(executablePath).parent.path;

      try {
        final devIcon = File('windows/runner/resources/app_icon.ico');
        if (devIcon.existsSync()) {
          return devIcon.absolute.path;
        }

        final resourceIcon = File('$executableDir\\resources\\app_icon.ico');
        if (resourceIcon.existsSync()) {
          return resourceIcon.absolute.path;
        }

        try {
          final tempDir = await getTemporaryDirectory();
          final iconFile = File('${tempDir.path}\\tray_icon.ico');

          try {
            final data = await rootBundle.load(
              'assets/icons/favicon.ico',
            );
            final bytes = data.buffer.asUint8List();
            await iconFile.writeAsBytes(bytes);
            _cachedIconPath = iconFile.absolute.path;
            return _cachedIconPath!;
          } on Exception catch (e) {
            _logger.w(
              'rootBundle not yet available, trying alternative method: $e',
            );
            // Se rootBundle não estiver disponível, retornar executável
            return executablePath;
          }
        } on Exception catch (e) {
          _logger.w('Failed to create temporary icon: $e');
          return executablePath;
        }
      } on Exception catch (e) {
        _logger.w('Could not copy icon from assets: $e');
      }

      final paths = [
        '$executableDir\\resources\\app_icon.ico',
        '$executableDir\\data\\flutter_assets\\assets\\icons\\favicon.ico',
        '${Directory(executablePath).parent.parent.path}\\data\\flutter_assets\\assets\\icons\\favicon.ico',
        '$executableDir\\assets\\icons\\favicon.ico',
      ];

      for (final path in paths) {
        final file = File(path);
        if (file.existsSync()) {
          return file.absolute.path;
        }
      }

      var currentDir = Directory(executablePath).parent;
      for (var i = 0; i < 6; i++) {
        final iconPath = '${currentDir.path}\\assets\\icons\\favicon.ico';
        final iconFile = File(iconPath);
        if (iconFile.existsSync()) {
          return iconFile.absolute.path;
        }
        final parent = currentDir.parent;
        if (parent.path == currentDir.path) break;
        currentDir = parent;
      }

      return executablePath;
    }
    return 'assets/icons/favicon.ico';
  }

  Future<void> _updateMenu() async {
    try {
      final menu = Menu(
        items: [
          MenuItem(key: 'show', label: _showWindowLabel),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: _exitLabel),
        ],
      );

      await trayManager.setContextMenu(menu);
    } on Exception catch (e, stackTrace) {
      _logger.e(
        'Failed to configure tray context menu',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> setStatus(String status) async {
    await trayManager.setToolTip('Plug Database - $status');
  }

  @override
  void onTrayIconMouseDown() {
    // Mouse-up is the single activation event. Handling both phases caused
    // duplicate window restores for one click.
  }

  @override
  void onTrayIconMouseUp() {
    if (!_interactionsEnabled) {
      return;
    }
    unawaited(
      _dispatchMenuAction(TrayMenuAction.show),
    );
  }

  Future<void> _dispatchMenuAction(TrayMenuAction action) async {
    final handler = _onMenuAction;
    if (handler == null) {
      _logger.w('Tray action ignored because no handler is registered');
      return;
    }

    try {
      await handler(action);
    } on Object catch (error, stackTrace) {
      _logger.e(
        'Tray action failed: ${action.name}',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!_interactionsEnabled) {
      return;
    }
    unawaited(
      _showContextMenu().catchError((Object e, StackTrace? s) {
        _logger.e(
          'Erro ao exibir menu de contexto (unhandled)',
          error: e,
          stackTrace: s,
        );
      }),
    );
  }

  @override
  void onTrayIconRightMouseUp() {}

  Future<void> _showContextMenu() async {
    if (!_isInitialized) {
      _logger.w('TrayManager is not initialized');
      return;
    }

    try {
      await _updateMenu();
      await Future<void>.delayed(WindowTimings.trayContextMenuDelay);
      await trayManager.popUpContextMenu();
    } on Exception catch (e, stackTrace) {
      _logger.e(
        'Failed to show context menu',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(_dispatchMenuAction(TrayMenuAction.show));
      case 'exit':
        unawaited(_dispatchMenuAction(TrayMenuAction.exit));
      default:
        _logger.w('Item de menu desconhecido: ${menuItem.key}');
    }
  }

  @override
  Future<void> dispose() => _disposeTray();
}
