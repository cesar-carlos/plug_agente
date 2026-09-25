import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IStartupPreferencesRepository {
  bool get startWithWindows;

  bool get minimizeToTray;

  bool get closeToTray;

  bool get isStartupServiceAvailable;

  DateTime? get lastAutostartLaunchAt;

  Future<Result<Unit>> persistStartWithWindows(bool value);

  Future<Result<Unit>> persistLastAutostartLaunchAt(DateTime value);

  Future<Result<Unit>> persistMinimizeToTray(bool value);

  Future<Result<Unit>> persistCloseToTray(bool value);

  Future<Result<bool>> readSystemStartupEnabled();

  /// True when Windows Startup Apps blocks the entry, including overlays that
  /// cannot be classified; boot and sync must not overwrite either case.
  Future<Result<bool>> readStartupDisabledByUser();

  Future<Result<Unit>> enableSystemStartup();

  Future<Result<Unit>> disableSystemStartup();

  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
    bool createIfMissing = true,
  });

  Future<Result<Unit>> openStartupSettings();

  Future<Result<String>> buildStartupDiagnosticReport();
}
