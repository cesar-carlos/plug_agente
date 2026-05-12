import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';

/// Resultado emitido após uma alteração de inicialização automática. Permite
/// que a UI apresente feedback de sucesso de forma desacoplada do provider.
enum StartupChangeOutcome {
  enabled,
  disabled,
}

class SystemSettingsProvider extends ChangeNotifier {
  SystemSettingsProvider(
    this._prefs, {
    IWindowManagerService? windowManagerService,
    IStartupService? startupService,
  }) : _windowManagerService = windowManagerService,
       _startupService = startupService {
    _startWithWindows = _prefs.getBool(AppSettingsKeys.startWithWindows) ?? false;
    _startMinimized = _prefs.getBool(AppSettingsKeys.startMinimized) ?? false;
    _minimizeToTray = _prefs.getBool(AppSettingsKeys.minimizeToTray) ?? true;
    _closeToTray = _prefs.getBool(AppSettingsKeys.closeToTray) ?? true;

    _initializeAsync();
  }

  Future<void> _initializeAsync() async {
    await _syncStartupStatus();
  }

  final IAppSettingsStore _prefs;
  final IWindowManagerService? _windowManagerService;
  final IStartupService? _startupService;
  late bool _startWithWindows;
  late bool _startMinimized;
  late bool _minimizeToTray;
  late bool _closeToTray;

  SystemSettingsErrorState? _startupError;
  SystemSettingsErrorState? _preferenceError;
  SystemSettingsNoticeState? _startupNotice;

  /// Backward-compatible view of the latest visible error.
  SystemSettingsErrorState? get lastError => _startupError ?? _preferenceError;

  SystemSettingsErrorState? get startupError => _startupError;
  SystemSettingsErrorState? get preferenceError => _preferenceError;
  SystemSettingsNoticeState? get startupNotice => _startupNotice;

  void clearError() {
    if (_startupError != null || _preferenceError != null || _startupNotice != null) {
      _startupError = null;
      _preferenceError = null;
      _startupNotice = null;
      notifyListeners();
    }
  }

  void clearStartupFeedback() {
    if (_startupError != null || _startupNotice != null) {
      _startupError = null;
      _startupNotice = null;
      notifyListeners();
    }
  }

  void clearPreferenceError() {
    if (_preferenceError != null) {
      _preferenceError = null;
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
          unawaited(_persistBoolSetting(AppSettingsKeys.startWithWindows, isEnabled));
          notifyListeners();
        }
        if (isEnabled) {
          _ensureStartupLaunchConfiguration(startupService);
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

  void _ensureStartupLaunchConfiguration(IStartupService startupService) {
    unawaited(
      startupService.ensureLaunchConfiguration().then((result) {
        result.fold(
          (status) {
            if (status == StartupLaunchConfigurationStatus.repaired) {
              _startupError = null;
              _startupNotice = const SystemSettingsNoticeState(
                code: SystemSettingsNoticeCode.startupLaunchConfigurationRepaired,
              );
              notifyListeners();
            }
          },
          (failure) {
            developer.log(
              'Failed to repair startup launch configuration: $failure',
              name: 'system_settings_provider',
              level: 900,
            );
            _startupNotice = SystemSettingsNoticeState(
              code: SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed,
              detail: failure is StartupServiceFailure ? failure.message : null,
            );
            notifyListeners();
          },
        );
      }),
    );
  }

  bool get startWithWindows => _startWithWindows;
  bool get startMinimized => _startMinimized;
  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;

  /// Atualiza o flag de inicialização com o Windows.
  ///
  /// Retorna [StartupChangeOutcome.enabled] ou [StartupChangeOutcome.disabled]
  /// quando a alteração foi aplicada (inclusive no SO, se o serviço estiver
  /// disponível). Retorna `null` quando nada mudou (no-op) ou quando houve
  /// falha — neste caso [lastError] é populado.
  Future<StartupChangeOutcome?> setStartWithWindows(bool value) async {
    if (_startWithWindows == value) {
      return null;
    }

    clearStartupFeedback();

    final startupService = _startupService;
    if (startupService != null) {
      final result = value ? await startupService.enable() : await startupService.disable();

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

          _startupError = SystemSettingsErrorState(
            code: SystemSettingsErrorCode.startupToggleFailed,
            detail: failure is StartupServiceFailure ? failure.message : null,
          );
          notifyListeners();

          return false;
        },
      );

      if (!success) {
        return null;
      }
    }

    if (!await _persistBoolSetting(AppSettingsKeys.startWithWindows, value)) {
      return null;
    }

    _startWithWindows = value;
    notifyListeners();
    return value ? StartupChangeOutcome.enabled : StartupChangeOutcome.disabled;
  }

  Future<void> repairStartupLaunchConfiguration() async {
    clearStartupFeedback();

    final startupService = _startupService;
    if (startupService == null) {
      _startupError = const SystemSettingsErrorState(
        code: SystemSettingsErrorCode.startupServiceUnavailable,
      );
      notifyListeners();
      return;
    }

    final result = await startupService.ensureLaunchConfiguration();
    result.fold(
      (status) {
        _startupError = null;
        _startupNotice = SystemSettingsNoticeState(
          code: status == StartupLaunchConfigurationStatus.repaired
              ? SystemSettingsNoticeCode.startupLaunchConfigurationRepaired
              : SystemSettingsNoticeCode.startupLaunchConfigurationReady,
        );
        notifyListeners();
      },
      (failure) {
        _startupNotice = SystemSettingsNoticeState(
          code: SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed,
          detail: failure is StartupServiceFailure ? failure.message : null,
        );
        notifyListeners();
      },
    );
  }

  Future<void> openStartupSettings() async {
    final startupService = _startupService;
    if (startupService == null) {
      _startupError = const SystemSettingsErrorState(
        code: SystemSettingsErrorCode.startupServiceUnavailable,
      );
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
        _startupError = SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupOpenSystemSettingsFailed,
          detail: failure is StartupServiceFailure ? failure.message : null,
        );
        notifyListeners();
      },
    );
  }

  Future<void> setStartMinimized(bool value) async {
    if (_startMinimized == value) {
      return;
    }

    clearPreferenceError();

    if (!await _persistBoolSetting(AppSettingsKeys.startMinimized, value)) {
      return;
    }

    _startMinimized = value;
    notifyListeners();
  }

  Future<void> setMinimizeToTray(bool value) async {
    if (_minimizeToTray == value) {
      return;
    }

    clearPreferenceError();

    if (!await _persistBoolSetting(AppSettingsKeys.minimizeToTray, value)) {
      return;
    }

    _minimizeToTray = value;
    notifyListeners();
    _windowManagerService?.setMinimizeToTray(value: value);
  }

  Future<void> setCloseToTray(bool value) async {
    if (_closeToTray == value) {
      return;
    }

    clearPreferenceError();

    if (!await _persistBoolSetting(AppSettingsKeys.closeToTray, value)) {
      return;
    }

    _closeToTray = value;
    notifyListeners();
    _windowManagerService?.setCloseToTray(value: value);
  }

  Future<bool> _persistBoolSetting(String key, bool value) async {
    try {
      await _prefs.setBool(key, value);
      return true;
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to persist setting $key',
        name: 'system_settings_provider',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      _preferenceError = SystemSettingsErrorState(
        code: SystemSettingsErrorCode.settingsPersistenceFailed,
        detail: error.toString(),
      );
      notifyListeners();
      return false;
    }
  }
}
