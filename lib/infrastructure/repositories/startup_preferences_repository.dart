import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class StartupPreferencesRepository implements IStartupPreferencesRepository {
  StartupPreferencesRepository(
    this._settings, {
    IStartupService? startupService,
  }) : _startupService = startupService;

  final IAppSettingsStore _settings;
  final IStartupService? _startupService;

  @override
  bool get startWithWindows =>
      _settings.getBool(AppSettingsKeys.startWithWindows) ?? false;

  @override
  bool get startMinimized =>
      _settings.getBool(AppSettingsKeys.startMinimized) ?? false;

  @override
  bool get minimizeToTray =>
      _settings.getBool(AppSettingsKeys.minimizeToTray) ?? true;

  @override
  bool get closeToTray => _settings.getBool(AppSettingsKeys.closeToTray) ?? true;

  @override
  bool get isStartupServiceAvailable => _startupService != null;

  @override
  Future<Result<Unit>> persistStartWithWindows(bool value) =>
      _persistBool(AppSettingsKeys.startWithWindows, value);

  @override
  Future<Result<Unit>> persistStartMinimized(bool value) =>
      _persistBool(AppSettingsKeys.startMinimized, value);

  @override
  Future<Result<Unit>> persistMinimizeToTray(bool value) =>
      _persistBool(AppSettingsKeys.minimizeToTray, value);

  @override
  Future<Result<Unit>> persistCloseToTray(bool value) =>
      _persistBool(AppSettingsKeys.closeToTray, value);

  @override
  Future<Result<bool>> readSystemStartupEnabled() {
    final startupService = _startupService;
    if (startupService == null) {
      return Future.value(
        Failure(
          domain.ConfigurationFailure('Startup service is unavailable'),
        ),
      );
    }
    return startupService.isEnabled();
  }

  @override
  Future<Result<Unit>> enableSystemStartup() {
    final startupService = _startupService;
    if (startupService == null) {
      return Future.value(
        Failure(
          domain.ConfigurationFailure('Startup service is unavailable'),
        ),
      );
    }
    return startupService.enable();
  }

  @override
  Future<Result<Unit>> disableSystemStartup() {
    final startupService = _startupService;
    if (startupService == null) {
      return Future.value(
        Failure(
          domain.ConfigurationFailure('Startup service is unavailable'),
        ),
      );
    }
    return startupService.disable();
  }

  @override
  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
  }) {
    final startupService = _startupService;
    if (startupService == null) {
      return Future.value(
        Failure(
          domain.ConfigurationFailure('Startup service is unavailable'),
        ),
      );
    }
    return startupService.ensureLaunchConfiguration(
      allowElevation: allowElevation,
    );
  }

  @override
  Future<Result<Unit>> openStartupSettings() {
    final startupService = _startupService;
    if (startupService == null) {
      return Future.value(
        Failure(
          domain.ConfigurationFailure('Startup service is unavailable'),
        ),
      );
    }
    return startupService.openSystemSettings();
  }

  @override
  Future<Result<String>> buildStartupDiagnosticReport() {
    final startupService = _startupService;
    if (startupService == null) {
      return Future.value(
        Failure(
          domain.ConfigurationFailure('Startup service is unavailable'),
        ),
      );
    }
    return startupService.buildStartupDiagnosticReport();
  }

  Future<Result<Unit>> _persistBool(String key, bool value) async {
    try {
      await _settings.setBool(key, value);
      return const Success(unit);
    } on Object catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to persist setting',
          cause: error,
          context: {'key': key},
        ),
      );
    }
  }
}
