import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:window_manager/window_manager.dart';

import '../constants/window_constraints.dart';
import '../constants/app_constants.dart';

class WindowManagerService with WindowListener {
  static final WindowManagerService _instance = WindowManagerService._();
  factory WindowManagerService() => _instance;
  WindowManagerService._();

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
      backgroundColor: ui.Color.fromARGB(0, 0, 0, 0),
      skipTaskbar: startMinimized,
      titleBarStyle: TitleBarStyle.normal,
      title: windowTitle,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) {
        await windowManager.hide();
        _logger.i('Aplicativo iniciado minimizado (oculto)');
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    });

    if (startMinimized) {
      await Future.delayed(const Duration(milliseconds: 200));
      final isVisible = await windowManager.isVisible();
      if (isVisible) {
        _logger.w('Janela ainda visível após hide(), tentando ocultar novamente...');
        await windowManager.hide();
        await windowManager.setSkipTaskbar(true);
      }
      _logger.i('Aplicativo iniciado minimizado - janela oculta');
    } else {
      await windowManager.setSkipTaskbar(false);
    }

    await windowManager.setMinimumSize(defaultMinimumSize);
    await windowManager.setPreventClose(false);

    windowManager.addListener(this);
    _isInitialized = true;

    _logger.i('WindowManager inicializado - Tamanho mínimo: ${defaultMinimumSize.width}x${defaultMinimumSize.height}');
  }

  void setCallbacks({VoidCallback? onMinimize, VoidCallback? onClose, VoidCallback? onFocus}) {
    _onMinimize = onMinimize;
    _onClose = onClose;
    _onFocus = onFocus;
  }

  void setMinimizeToTray(bool value) {
    _minimizeToTray = value;
    _logger.d('Minimizar para bandeja: $value');
  }

  void setCloseToTray(bool value) {
    _closeToTray = value;
    _logger.d('Fechar para bandeja: $value');

    _updatePreventClose(value).catchError((e) {
      _logger.w('Erro ao configurar preventClose: $e');
    });
  }

  Future<void> _updatePreventClose(bool closeToTray) async {
    try {
      if (closeToTray) {
        await windowManager.setPreventClose(true);
        _logger.d('PreventClose ativado - fechar irá para bandeja');
      } else {
        await windowManager.setPreventClose(false);
        _logger.d('PreventClose desativado - fechar irá encerrar aplicativo');
      }
    } catch (e) {
      _logger.w('Erro ao configurar preventClose: $e');
    }
  }

  Future<void> show() async {
    try {
      _logger.i('🪟 Mostrando janela...');

      await windowManager.setSkipTaskbar(false);
      await Future.delayed(const Duration(milliseconds: 100));

      final isMinimized = await windowManager.isMinimized();
      final isVisible = await windowManager.isVisible();

      _logger.i('📊 Estado antes de mostrar - Minimizada: $isMinimized, Visível: $isVisible');

      if (isMinimized) {
        _logger.i('🔄 Janela está minimizada, restaurando...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logger.i('👁️ Chamando show()...');
      await windowManager.show();
      await Future.delayed(const Duration(milliseconds: 200));

      final isVisibleAfterShow = await windowManager.isVisible();
      _logger.i('📊 Visível após show(): $isVisibleAfterShow');

      if (!isVisibleAfterShow) {
        _logger.w('⚠️ Janela ainda não está visível após show(), tentando restaurar...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      _logger.i('🎯 Focando janela...');
      await windowManager.focus();
      await Future.delayed(const Duration(milliseconds: 100));

      final finalIsVisible = await windowManager.isVisible();
      final finalIsMinimized = await windowManager.isMinimized();
      _logger.i('✅ Janela exibida! Visível: $finalIsVisible, Minimizada: $finalIsMinimized');

      if (!finalIsVisible) {
        _logger.e('❌ CRÍTICO: Janela ainda não está visível após todas as tentativas!');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 300));
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e, stackTrace) {
      _logger.e('❌ Erro ao mostrar janela', error: e, stackTrace: stackTrace);
      try {
        _logger.i('🔄 Tentando método alternativo...');
        await windowManager.restore();
        await Future.delayed(const Duration(milliseconds: 200));
        await windowManager.show();
        await windowManager.focus();
      } catch (e2) {
        _logger.e('❌ Erro crítico ao mostrar janela', error: e2);
        rethrow;
      }
    }
  }

  Future<void> restore() async {
    await windowManager.restore();
    await Future.delayed(const Duration(milliseconds: 200));
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
      _logger.i('Fechando aplicativo...');
      
      // Marcar como fechamento intencional
      _isClosing = true;
      
      // Desabilitar closeToTray temporariamente para permitir fechamento real
      _closeToTray = false;
      
      // Desabilitar preventClose para permitir fechamento
      await windowManager.setPreventClose(false);
      
      // Fechar a janela
      await windowManager.close();
      
      _logger.i('Aplicativo fechado');
    } catch (e, stackTrace) {
      _logger.e('Erro ao fechar aplicativo', error: e, stackTrace: stackTrace);
      // Forçar saída mesmo com erro
      exit(0);
    }
  }

  Future<void> setTitle(String title) async {
    await windowManager.setTitle(title);
  }

  Future<bool> isVisible() async {
    return await windowManager.isVisible();
  }

  Future<bool> isMinimized() async {
    return await windowManager.isMinimized();
  }

  Future<bool> isFocused() async {
    return await windowManager.isFocused();
  }

  // WindowListener callbacks
  @override
  void onWindowMinimize() {
    if (_minimizeToTray) {
      hide().catchError((e) {
        _logger.e('Erro ao ocultar janela ao minimizar', error: e);
      });
    }
    _onMinimize?.call();
  }

  @override
  void onWindowClose() async {
    // Se já estamos fechando intencionalmente, permitir fechamento
    if (_isClosing) {
      _logger.d('Fechamento intencional - permitindo');
      return;
    }

    _logger.i('Tentativa de fechar janela - closeToTray: $_closeToTray');

    try {
      final isPreventClose = await windowManager.isPreventClose();
      if (isPreventClose && !_closeToTray) {
        _logger.d('Fechamento prevenido por outro motivo - ignorando evento');
        return;
      }
    } catch (e) {
      _logger.w('Erro ao verificar preventClose: $e');
    }

    if (_closeToTray) {
      try {
        await windowManager.setPreventClose(true);
        await hide();
        await windowManager.setSkipTaskbar(true);
        _logger.i('✅ Janela ocultada para a bandeja (fechamento prevenido)');
      } catch (e) {
        _logger.e('Erro ao ocultar janela para bandeja', error: e);
        try {
          await hide();
          await windowManager.setSkipTaskbar(true);
        } catch (e2) {
          _logger.e('Erro crítico ao ocultar janela', error: e2);
        }
      }
    } else {
      try {
        await windowManager.setPreventClose(false);
        _logger.i('Fechamento permitido - encerrando aplicativo');
        _onClose?.call();
      } catch (e) {
        _logger.e('Erro ao configurar preventClose para fechar', error: e);
        _onClose?.call();
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
