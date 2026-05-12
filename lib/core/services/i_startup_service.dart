import 'package:result_dart/result_dart.dart';

enum StartupLaunchConfigurationStatus {
  unchanged,
  repaired,
}

abstract interface class IStartupService {
  Future<Result<bool>> isEnabled();

  Future<Result<StartupLaunchConfigurationStatus>> ensureLaunchConfiguration();

  Future<Result<Unit>> enable();

  Future<Result<Unit>> disable();

  Future<Result<Unit>> openSystemSettings();
}
