import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';

class SystemSettingsProvider extends ChangeNotifier {
  SystemSettingsProvider(
    this._prefs, {
    IWindowManagerService? windowManagerService,
    IStartupService? startupService,
  }) : _windowManagerService = windowManagerService,
       _startupService = startupService {
    _startWithWindows = _prefs.getBool(_startWithWindowsKey) ?? false;
    _startMinimized = _prefs.getBool(_startMinimizedKey) ?? false;
    _minimizeToTray = _prefs.getBool(_minimizeToTrayKey) ?? true;
    _closeToTray = _prefs.getBool(_closeToTrayKey) ?? true;

    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await _syncStartupStatus();
  }

  static const String _startWithWindowsKey = 'settings.start_with_windows';
  static const String _startMinimizedKey = 'settings.start_minimized';
  static const String _minimizeToTrayKey = 'settings.minimize_to_tray';
  static const String _closeToTrayKey = 'settings.close_to_tray';

  final IAppSettingsStore _prefs;
  final IWindowManagerService? _windowManagerService;
  final IStartupService? _startupService;
  late bool _startWithWindows;
  late bool _startMinimized;
  late bool _minimizeToTray;
  late bool _closeToTray;

  String? _lastError;
  String? get lastError => _lastError;

  void clearError() {
    if (_lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }

  Future<void> _syncStartupStatus() async {
    final startupService = _startupService;
    if (startupService == null) {
      return;
    }

    final result = await startupService.isEnabled();
    result.fold(
      (isEnabled) {
        if (isEnabled != _startWithWindows) {
          developer.log(
            'Startup status out of sync (system: $isEnabled, settings: $_startWithWindows), updating settings',
            name: 'system_settings_provider',
            level: 800,
          );
          _startWithWindows = isEnabled;
          _prefs.setBool(_startWithWindowsKey, isEnabled);
          notifyListeners();
        }
      },
      (failure) {
        developer.log(
          'Failed to sync startup status: $failure',
          name: 'system_settings_provider',
          level: 900,
        );
      },
    );
  }

  bool get startWithWindows => _startWithWindows;
  bool get startMinimized => _startMinimized;
  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;

  Future<void> setStartWithWindows(bool value) async {
    if (_startWithWindows == value) {
      return;
    }

    clearError();

    final startupService = _startupService;
    if (startupService != null) {
      final result = value
          ? await startupService.enable()
          : await startupService.disable();

      final success = result.fold(
        (_) {
          developer.log(
            'Startup ${value ? "enabled" : "disabled"} successfully',
            name: 'system_settings_provider',
            level: 800,
          );
          return true;
        },
        (failure) {
          developer.log(
            'Failed to ${value ? "enable" : "disable"} startup: $failure',
            name: 'system_settings_provider',
            level: 900,
          );

          _lastError = failure is StartupServiceFailure
              ? failure.message
              : 'Falha ao alterar configuração de inicialização';
          notifyListeners();

          return false;
        },
      );

      if (!success) {
        return;
      }
    }

    _startWithWindows = value;
    notifyListeners();
    await _prefs.setBool(_startWithWindowsKey, value);
  }

  Future<void> openStartupSettings() async {
    final startupService = _startupService;
    if (startupService == null) {
      _lastError =
          'Configurações de inicialização não disponíveis neste ambiente';
      notifyListeners();
      return;
    }

    final result = await startupService.openSystemSettings();
    result.fold(
      (_) {
        developer.log(
          'Opened startup settings successfully',
          name: 'system_settings_provider',
          level: 800,
        );
      },
      (failure) {
        _lastError = failure is StartupServiceFailure
            ? failure.message
            : 'Falha ao abrir configurações do sistema';
        notifyListeners();
      },
    );
  }

  Future<void> setStartMinimized(bool value) async {
    if (_startMinimized == value) {
      return;
    }

    _startMinimized = value;
    notifyListeners();
    await _prefs.setBool(_startMinimizedKey, value);
  }

  Future<void> setMinimizeToTray(bool value) async {
    if (_minimizeToTray == value) {
      return;
    }

    _minimizeToTray = value;
    notifyListeners();
    await _prefs.setBool(_minimizeToTrayKey, value);

    _windowManagerService?.setMinimizeToTray(value: value);
  }

  Future<void> setCloseToTray(bool value) async {
    if (_closeToTray == value) {
      return;
    }

    _closeToTray = value;
    notifyListeners();
    await _prefs.setBool(_closeToTrayKey, value);

    _windowManagerService?.setCloseToTray(value: value);
  }
}
