import 'dart:developer' as developer;

import 'package:plug_agente/core/services/i_tray_service.dart';

/// Implementação noop de TrayManagerService para ambientes sem suporte a tray.
class NoopTrayManagerService implements ITrayService {
  factory NoopTrayManagerService() => _instance;
  NoopTrayManagerService._();
  static final NoopTrayManagerService _instance = NoopTrayManagerService._();

  bool _isInitialized = false;
  bool _didLogUnavailable = false;

  @override
  Future<void> initialize({
    void Function(TrayMenuAction)? onMenuAction,
  }) async {
    if (_isInitialized) return;

    if (!_didLogUnavailable) {
      developer.log(
        'Tray manager not available in degraded mode',
        name: 'noop_tray_manager_service',
        level: 800,
      );
      _didLogUnavailable = true;
    }

    _isInitialized = true;
  }

  @override
  Future<void> setStatus(String status) async {
    // Noop
  }

  @override
  void dispose() {
    // Noop
  }
}
