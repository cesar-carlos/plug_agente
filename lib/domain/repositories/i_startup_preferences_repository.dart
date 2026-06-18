import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IStartupPreferencesRepository {
  bool get startWithWindows;

  bool get startMinimized;

  bool get minimizeToTray;

  bool get closeToTray;

  bool get isStartupServiceAvailable;

  Future<Result<Unit>> persistStartWithWindows(bool value);

  Future<Result<Unit>> persistStartMinimized(bool value);

  Future<Result<Unit>> persistMinimizeToTray(bool value);

  Future<Result<Unit>> persistCloseToTray(bool value);

  Future<Result<bool>> readSystemStartupEnabled();

  Future<Result<Unit>> enableSystemStartup();

  Future<Result<Unit>> disableSystemStartup();

  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
  });

  Future<Result<Unit>> openStartupSettings();

  Future<Result<String>> buildStartupDiagnosticReport();

  Future<Result<bool>> hasRegistryEntryMissingAutostartForCurrentExecutable();
}
