import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:tray_manager/tray_manager.dart';

class TrayManagerService with TrayListener implements ITrayService {
  factory TrayManagerService() => _instance;
  TrayManagerService._();
  static final TrayManagerService _instance = TrayManagerService._();

  final Logger _logger = Logger();
  void Function(TrayMenuAction)? _onMenuAction;
  bool _isInitialized = false;
  String? _cachedIconPath;

  @override
  Future<void> initialize({
    void Function(TrayMenuAction)? onMenuAction,
  }) async {
    if (_isInitialized) return;

    _onMenuAction = onMenuAction;
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
    } on Exception catch (e, stackTrace) {
      _logger.e(
        'Erro ao configurar ícone da bandeja',
        error: e,
        stackTrace: stackTrace,
      );
      try {
        final executablePath = Platform.resolvedExecutable;
        await trayManager.setIcon(executablePath);
      } on Exception catch (e2) {
        _logger.e('Erro crítico ao configurar ícone', error: e2);
      }
    }

    try {
      await trayManager.setToolTip('Plug Database');
      await Future<void>.delayed(AppConstants.trayInitDelay);

      await _updateMenu();
      await Future<void>.delayed(AppConstants.trayInitDelay);

      _isInitialized = true;
      _logger.i('TrayManager inicializado');
    } on Exception catch (e, stackTrace) {
      _logger.e(
        'Erro durante inicialização do TrayManager',
        error: e,
        stackTrace: stackTrace,
      );
      // Mesmo com erro, marcar como inicializado para evitar loops
      _isInitialized = true;
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
              'rootBundle não disponível ainda, tentando método alternativo: $e',
            );
            // Se rootBundle não estiver disponível, retornar executável
            return executablePath;
          }
        } on Exception catch (e) {
          _logger.w('Erro ao criar ícone temporário: $e');
          return executablePath;
        }
      } on Exception catch (e) {
        _logger.w('Não foi possível copiar ícone dos assets: $e');
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
          MenuItem(key: 'show', label: 'Abrir Plug Database'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: 'Sair'),
        ],
      );

      await trayManager.setContextMenu(menu);
    } on Exception catch (e, stackTrace) {
      _logger.e(
        'Erro ao configurar menu de contexto',
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
    unawaited(
      Future<void>.delayed(AppConstants.trayIconClickDelay, () {
        unawaited(
          _restoreWindow()
              .then((_) => _onMenuAction?.call(TrayMenuAction.show))
              .catchError((Object e, StackTrace? s) {
                _logger.e(
                  'Erro ao restaurar janela do tray',
                  error: e,
                  stackTrace: s,
                );
              }),
        );
      }).catchError((Object e, StackTrace s) {
        _logger.e(
          'Tray icon delayed restore failed',
          error: e,
          stackTrace: s,
        );
      }),
    );
  }

  @override
  void onTrayIconMouseUp() {
    unawaited(
      _restoreWindow()
          .then((_) => _onMenuAction?.call(TrayMenuAction.show))
          .catchError((Object e) {
            _logger.e('Erro ao restaurar janela do tray', error: e);
          }),
    );
  }

  Future<void> _restoreWindow() async {
    if (!getIt.isRegistered<IWindowManagerService>()) {
      _logger.w('Window manager not available');
      return;
    }
    final windowManager = getIt<IWindowManagerService>();
    await windowManager.show();
  }

  @override
  void onTrayIconRightMouseDown() {
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
      _logger.w('TrayManager não está inicializado');
      return;
    }

    try {
      await _updateMenu();
      await Future<void>.delayed(AppConstants.trayContextMenuDelay);
      await trayManager.popUpContextMenu();
    } on Exception catch (e, stackTrace) {
      _logger.e(
        'Erro ao exibir menu de contexto',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        unawaited(
          _restoreWindow()
              .then((_) => _onMenuAction?.call(TrayMenuAction.show))
              .catchError((Object e) {
                _logger.e('Erro ao restaurar janela do menu', error: e);
              }),
        );
      case 'exit':
        _onMenuAction?.call(TrayMenuAction.exit);
      default:
        _logger.w('Item de menu desconhecido: ${menuItem.key}');
    }
  }

  @override
  void dispose() {
    unawaited(
      (trayManager..removeListener(this)).destroy().catchError(
        (Object e, StackTrace? s) => _logger.w(
          'Tray destroy failed',
          error: e,
          stackTrace: s,
        ),
      ),
    );
  }
}
