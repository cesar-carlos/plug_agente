import 'package:result_dart/result_dart.dart';

enum InstallationPreparationState { waiting, closing, blocked, cancelled, recoveryRequired }

abstract interface class IInstallationPreparation {
  InstallationPreparationState get state;
  Future<Result<InstallationPreparationState>> prepare(String operation);
  Future<Result<void>> close();
  void cancel();
}

abstract interface class IInstallationPreparationMonitor {
  Future<void> start();
  void stop();
}
