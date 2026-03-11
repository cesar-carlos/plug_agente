import 'dart:developer' as developer;

import 'package:plug_agente/core/services/tray_manager_service.dart';
import 'package:tray_manager/tray_manager.dart';

/// Implementação noop de TrayManagerService para ambientes sem suporte a tray.
class NoopTrayManagerService with TrayListener {
  factory NoopTrayManagerService() => _instance;
  NoopTrayManagerService._();
  static final NoopTrayManagerService _instance = NoopTrayManagerService._();

  bool _isInitialized = false;

  Future<void> initialize({
    void Function(TrayMenuAction)? onMenuAction,
  }) async {
    if (_isInitialized) return;

    developer.log(
      'Tray manager not available in degraded mode',
      name: 'noop_tray_manager_service',
      level: 800,
    );

    _isInitialized = true;
  }

  Future<void> setStatus(String status) async {
    // Noop
  }

  @override
  void onTrayIconMouseDown() {
    // Noop
  }

  @override
  void onTrayIconMouseUp() {
    // Noop
  }

  @override
  void onTrayIconRightMouseDown() {
    // Noop
  }

  @override
  void onTrayIconRightMouseUp() {
    // Noop
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    // Noop
  }

  void dispose() {
    // Noop
  }
}
