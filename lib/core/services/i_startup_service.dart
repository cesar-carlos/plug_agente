import 'package:result_dart/result_dart.dart';

enum StartupLaunchConfigurationStatus {
  unchanged,
  repaired,
  needsRepair,
  repairedWithLegacyMachineEntry,
}

abstract interface class IStartupService {
  Future<Result<bool>> isEnabled();

  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration({
    bool allowElevation = true,
    bool createIfMissing = true,
  });

  Future<Result<Unit>> enable();

  Future<Result<Unit>> disable();

  Future<Result<Unit>> openSystemSettings();

  Future<Result<String>> buildStartupDiagnosticReport();
}
