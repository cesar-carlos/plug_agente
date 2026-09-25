import 'package:result_dart/result_dart.dart';

enum StartupLaunchConfigurationStatus {
  unchanged,
  repaired,
  needsRepair,
  repairedWithLegacyMachineEntry,
}

abstract interface class IStartupService {
  Future<Result<bool>> isEnabled();

  /// True when the Startup Apps overlay blocks the entry, including values
  /// that cannot be classified.
  ///
  /// Must not treat `accessDenied` or `failed` reads as disabled.
  Future<Result<bool>> isDisabledByStartupApps();

  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
    bool createIfMissing = true,
  });

  Future<Result<Unit>> enable();

  Future<Result<Unit>> disable();

  Future<Result<Unit>> openSystemSettings();

  /// Registry and Startup Apps section of the startup diagnostic.
  Future<Result<String>> buildStartupDiagnosticReport();
}
