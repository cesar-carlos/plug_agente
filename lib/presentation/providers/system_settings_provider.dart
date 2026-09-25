import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/build_startup_diagnostic_report.dart';
import 'package:plug_agente/application/use_cases/set_start_with_windows.dart';
import 'package:plug_agente/application/use_cases/set_tray_behavior_preference.dart';
import 'package:plug_agente/application/use_cases/startup_launch_configuration_mapper.dart';
import 'package:plug_agente/application/use_cases/sync_startup_status.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/system_settings_failure_mapper.dart';

export 'package:plug_agente/application/models/startup_preferences_outcomes.dart' show StartupChangeOutcome;

class SystemSettingsProvider extends ChangeNotifier {
  SystemSettingsProvider(
    IStartupPreferencesRepository repository, {
    SyncStartupStatus? syncStartupStatus,
    SetStartWithWindows? setStartWithWindows,
    SetTrayBehaviorPreference? setTrayBehaviorPreference,
    BuildStartupDiagnosticReport? buildStartupDiagnosticReport,
  }) : _repository = repository,
       _syncStartupStatus = syncStartupStatus ?? SyncStartupStatus(repository),
       _setStartWithWindows = setStartWithWindows ?? SetStartWithWindows(repository),
       _setTrayBehaviorPreference = setTrayBehaviorPreference ?? SetTrayBehaviorPreference(repository),
       _buildStartupDiagnosticReport = buildStartupDiagnosticReport ?? BuildStartupDiagnosticReport(repository) {
    _startWithWindows = repository.startWithWindows;
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
  final BuildStartupDiagnosticReport _buildStartupDiagnosticReport;

  late bool _startWithWindows;
  late bool _minimizeToTray;
  late bool _closeToTray;
  bool _isDisposed = false;
  int _startupUserMutations = 0;
  bool _isChangingStartWithWindows = false;
  bool _isChangingMinimizeToTray = false;
  bool _isChangingCloseToTray = false;

  SystemSettingsErrorState? _startupError;
  SystemSettingsErrorState? _preferenceError;
  SystemSettingsNoticeState? _startupNotice;

  SystemSettingsErrorState? get lastError => _startupError ?? _preferenceError;
  SystemSettingsErrorState? get startupError => _startupError;
  SystemSettingsErrorState? get preferenceError => _preferenceError;
  SystemSettingsNoticeState? get startupNotice => _startupNotice;

  bool get startWithWindows => _startWithWindows;
  bool get minimizeToTray => _minimizeToTray;
  bool get closeToTray => _closeToTray;
  bool get isChangingStartWithWindows => _isChangingStartWithWindows;
  bool get isChangingMinimizeToTray => _isChangingMinimizeToTray;
  bool get isChangingCloseToTray => _isChangingCloseToTray;

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
    final mutationsAtStart = _startupUserMutations;
    final result = await _syncStartupStatus(
      shouldAbort: () => _isDisposed || _startupUserMutations != mutationsAtStart,
    );
    if (_isDisposed || _startupUserMutations != mutationsAtStart) {
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
    if (_isChangingStartWithWindows || _startWithWindows == value) {
      return null;
    }

    _startupUserMutations++;
    _isChangingStartWithWindows = true;
    clearStartupFeedback();
    _notifyIfActive();

    try {
      final result = await _setStartWithWindows(value);
      if (_isDisposed) {
        return null;
      }

      return await result.fold(
        (outcome) {
          _startWithWindows = value;
          _applyLaunchConfigurationOutcome(outcome.launchConfiguration);
          return outcome.change;
        },
        (failure) {
          if (failure is StartupServiceFailure) {
            _startupError = SystemSettingsFailureMapper.startupFailure(failure);
          } else if (failure is domain.Failure) {
            _preferenceError = SystemSettingsFailureMapper.preferenceFailure(failure);
          } else {
            _startupError = SystemSettingsFailureMapper.startupFailure(failure);
          }
          return null;
        },
      );
    } finally {
      if (!_isDisposed) {
        _isChangingStartWithWindows = false;
        _notifyIfActive();
      }
    }
  }

  Future<void> repairStartupLaunchConfiguration() async {
    _startupUserMutations++;
    clearStartupFeedback();

    if (!_repository.isStartupServiceAvailable) {
      _startupError = const SystemSettingsErrorState(
        code: SystemSettingsErrorCode.startupServiceUnavailable,
      );
      _notifyIfActive();
      return;
    }

    final outcome = await StartupLaunchConfigurationMapper.validate(
      _repository,
      createIfMissing: _startWithWindows,
    );
    if (_isDisposed) {
      return;
    }
    _applyLaunchConfigurationOutcome(outcome);
    await _syncStartWithWindowsAfterRepair(outcome);
    if (_isDisposed) {
      return;
    }
    _notifyIfActive();
  }

  Future<bool> copyStartupDiagnosticToClipboard() async {
    if (!_repository.isStartupServiceAvailable) {
      return false;
    }

    final result = await _buildStartupDiagnosticReport();
    if (_isDisposed) {
      return false;
    }

    return result.fold(
      (report) async {
        try {
          await Clipboard.setData(ClipboardData(text: report));
          return true;
        } on Object catch (error, stackTrace) {
          developer.log(
            'Failed to copy startup diagnostic to clipboard',
            name: 'system_settings_provider',
            level: 900,
            error: error,
            stackTrace: stackTrace,
          );
          return false;
        }
      },
      (failure) {
        developer.log(
          'Failed to build startup diagnostic: $failure',
          name: 'system_settings_provider',
          level: 900,
        );
        return false;
      },
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

  Future<void> setMinimizeToTray(bool value) async {
    if (_isChangingMinimizeToTray || _minimizeToTray == value) {
      return;
    }

    _isChangingMinimizeToTray = true;
    clearPreferenceError();
    _notifyIfActive();
    try {
      await _applyTrayBehaviorPreference(TrayBehaviorKind.minimizeToTray, value);
    } finally {
      if (!_isDisposed) {
        _isChangingMinimizeToTray = false;
        _notifyIfActive();
      }
    }
  }

  Future<void> setCloseToTray(bool value) async {
    if (_isChangingCloseToTray || _closeToTray == value) {
      return;
    }

    _isChangingCloseToTray = true;
    clearPreferenceError();
    _notifyIfActive();
    try {
      await _applyTrayBehaviorPreference(TrayBehaviorKind.closeToTray, value);
    } finally {
      if (!_isDisposed) {
        _isChangingCloseToTray = false;
        _notifyIfActive();
      }
    }
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

  Future<void> _syncStartWithWindowsAfterRepair(StartupLaunchConfigurationOutcome? outcome) async {
    final type = outcome?.type;
    if (type == StartupLaunchConfigurationOutcomeType.repairFailed ||
        type == StartupLaunchConfigurationOutcomeType.needsRepair) {
      return;
    }

    final enabledResult = await _repository.readSystemStartupEnabled();
    if (_isDisposed) {
      return;
    }

    await enabledResult.fold(
      (enabled) async {
        if (_startWithWindows == enabled) {
          return;
        }

        final persistResult = await _repository.persistStartWithWindows(enabled);
        if (_isDisposed) {
          return;
        }
        persistResult.fold(
          (_) {
            _startWithWindows = enabled;
          },
          (failure) {
            _preferenceError = SystemSettingsFailureMapper.preferenceFailure(failure);
          },
        );
      },
      (failure) async {
        // The repair itself succeeded; this post-repair reconciliation is
        // best-effort. Surfacing a "toggle failed" error here would
        // contradict the repair notice the user just received.
        developer.log(
          'Failed to read startup status after repair: $failure',
          name: 'system_settings_provider',
          level: 900,
        );
      },
    );
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
