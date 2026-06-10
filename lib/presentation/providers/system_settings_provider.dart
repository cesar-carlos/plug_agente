import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/set_start_with_windows.dart';
import 'package:plug_agente/application/use_cases/set_tray_behavior_preference.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/application/use_cases/sync_startup_status.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/system_settings_failure_mapper.dart';

export 'package:plug_agente/application/models/startup_preferences_outcomes.dart'
    show StartupChangeOutcome;

class SystemSettingsProvider extends ChangeNotifier {
  SystemSettingsProvider(
    IStartupPreferencesRepository repository, {
    SyncStartupStatus? syncStartupStatus,
    SetStartWithWindows? setStartWithWindows,
    SetTrayBehaviorPreference? setTrayBehaviorPreference,
  }) : _repository = repository,
       _syncStartupStatus = syncStartupStatus ?? SyncStartupStatus(repository),
       _setStartWithWindows = setStartWithWindows ?? SetStartWithWindows(repository),
       _setTrayBehaviorPreference =
           setTrayBehaviorPreference ?? SetTrayBehaviorPreference(repository) {
    _startWithWindows = repository.startWithWindows;
    _startMinimized = repository.startMinimized;
    _minimizeToTray = repository.minimizeToTray;
    _closeToTray = repository.closeToTray;

    unawaited(
      _initializeAsync().catchError((Object error, StackTrace stackTrace) {
        developer.log(
          'Failed to initialize system settings provider',
          name: 'system_settings_provider',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
      }),
    );
  }

  final IStartupPreferencesRepository _repository;
  final SyncStartupStatus _syncStartupStatus;
  final SetStartWithWindows _setStartWithWindows;
  final SetTrayBehaviorPreference _setTrayBehaviorPreference;

  late bool _startWithWindows;
  late bool _startMinimized;
  late bool _minimizeToTray;
  late bool _closeToTray;
  bool _isDisposed = false;

  SystemSettingsErrorState? _startupError;
  SystemSettingsErrorState? _preferenceError;
  SystemSettingsNoticeState? _startupNotice;

  SystemSettingsErrorState? get lastError => _startupError ?? _preferenceError;
  SystemSettingsErrorState? get startupError => _startupError;
  SystemSettingsErrorState? get preferenceError => _preferenceError;
  SystemSettingsNoticeState? get startupNotice => _startupNotice;

  bool get startWithWindows => _startWithWindows;
  bool get startMinimized => _startMinimized;
  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;

  void clearError() {
    if (_startupError != null || _preferenceError != null || _startupNotice != null) {
      _startupError = null;
      _preferenceError = null;
      _startupNotice = null;
      _notifyIfActive();
    }
  }

  void clearStartupFeedback() {
    if (_startupError != null || _startupNotice != null) {
      _startupError = null;
      _startupNotice = null;
      _notifyIfActive();
    }
  }

  void clearPreferenceError() {
    if (_preferenceError != null) {
      _preferenceError = null;
      _notifyIfActive();
    }
  }

  Future<void> _initializeAsync() async {
    final result = await _syncStartupStatus();
    if (_isDisposed) {
      return;
    }

    result.fold(
      (outcome) {
        if (outcome.reconciledStartWithWindows != null) {
          _startWithWindows = outcome.reconciledStartWithWindows!;
        }
        if (outcome.launchConfiguration != null) {
          _applyLaunchConfigurationOutcome(outcome.launchConfiguration);
        }
        _notifyIfActive();
      },
      (failure) {
        _startupError = SystemSettingsFailureMapper.startupFailure(failure);
        _notifyIfActive();
      },
    );
  }

  Future<StartupChangeOutcome?> setStartWithWindows(bool value) async {
    if (_startWithWindows == value) {
      return null;
    }

    clearStartupFeedback();

    final result = await _setStartWithWindows(value);
    if (_isDisposed) {
      return null;
    }

    return result.fold(
      (outcome) {
        _startWithWindows = value;
        if (!outcome.preferencePersisted) {
          _preferenceError = const SystemSettingsErrorState(
            code: SystemSettingsErrorCode.settingsPersistenceFailed,
          );
        }
        _applyLaunchConfigurationOutcome(outcome.launchConfiguration);
        _notifyIfActive();
        return outcome.change;
      },
      (failure) {
        _startupError = SystemSettingsFailureMapper.startupFailure(failure);
        _notifyIfActive();
        return null;
      },
    );
  }

  Future<void> repairStartupLaunchConfiguration() async {
    clearStartupFeedback();

    if (!_repository.isStartupServiceAvailable) {
      _startupError = const SystemSettingsErrorState(
        code: SystemSettingsErrorCode.startupServiceUnavailable,
      );
      _notifyIfActive();
      return;
    }

    final outcome = await StartupLaunchConfigurationMapper.validate(_repository);
    if (_isDisposed) {
      return;
    }
    _applyLaunchConfigurationOutcome(outcome);
    _notifyIfActive();
  }

  Future<bool> copyStartupDiagnosticToClipboard() async {
    if (!_repository.isStartupServiceAvailable) {
      return false;
    }

    final result = await _repository.buildStartupDiagnosticReport();
    if (_isDisposed) {
      return false;
    }

    return result.fold(
      (report) async {
        await Clipboard.setData(ClipboardData(text: report));
        return true;
      },
      (_) => false,
    );
  }

  Future<void> openStartupSettings() async {
    if (!_repository.isStartupServiceAvailable) {
      _startupError = const SystemSettingsErrorState(
        code: SystemSettingsErrorCode.startupServiceUnavailable,
      );
      _notifyIfActive();
      return;
    }

    final result = await _repository.openStartupSettings();
    if (_isDisposed) {
      return;
    }

    result.fold(
      (_) {},
      (failure) {
        _startupError = SystemSettingsFailureMapper.openSystemSettingsFailure(failure);
        if (failure is StartupServiceFailure) {
          developer.log(
            failure.message,
            name: 'system_settings_provider',
            level: 900,
          );
        }
        _notifyIfActive();
      },
    );
  }

  Future<void> setStartMinimized(bool value) async {
    if (_startMinimized == value) {
      return;
    }

    clearPreferenceError();

    final result = await _repository.persistStartMinimized(value);
    if (_isDisposed) {
      return;
    }

    result.fold(
      (_) {
        _startMinimized = value;
        _notifyIfActive();
      },
      (failure) {
        _preferenceError = SystemSettingsFailureMapper.preferenceFailure(failure);
        _notifyIfActive();
      },
    );
  }

  Future<void> setMinimizeToTray(bool value) async {
    if (_minimizeToTray == value) {
      return;
    }

    clearPreferenceError();
    await _applyTrayBehaviorPreference(TrayBehaviorKind.minimizeToTray, value);
  }

  Future<void> setCloseToTray(bool value) async {
    if (_closeToTray == value) {
      return;
    }

    clearPreferenceError();
    await _applyTrayBehaviorPreference(TrayBehaviorKind.closeToTray, value);
  }

  Future<void> _applyTrayBehaviorPreference(TrayBehaviorKind kind, bool value) async {
    final result = await _setTrayBehaviorPreference(kind, value);
    if (_isDisposed) {
      return;
    }

    result.fold(
      (appliedValue) {
        switch (kind) {
          case TrayBehaviorKind.minimizeToTray:
            _minimizeToTray = appliedValue;
          case TrayBehaviorKind.closeToTray:
            _closeToTray = appliedValue;
        }
        _notifyIfActive();
      },
      (failure) {
        _preferenceError = SystemSettingsFailureMapper.preferenceFailure(failure);
        _notifyIfActive();
      },
    );
  }

  void _applyLaunchConfigurationOutcome(StartupLaunchConfigurationOutcome? outcome) {
    _startupError = null;
    _startupNotice = SystemSettingsFailureMapper.noticeFromLaunchOutcome(outcome);
  }

  void _notifyIfActive() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
