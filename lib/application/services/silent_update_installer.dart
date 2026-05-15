import 'package:result_dart/result_dart.dart';

enum SilentUpdateInstallStrategy {
  currentUserThenElevated,
  elevatedOnly,
}

class SilentUpdateInstallRequest {
  const SilentUpdateInstallRequest({
    required this.version,
    required this.assetUrl,
    required this.assetSize,
    required this.assetName,
    required this.sha256,
    required this.requireValidSignature,
  });

  final String version;
  final String assetUrl;
  final int assetSize;
  final String assetName;
  final String sha256;
  final bool requireValidSignature;
}

class SilentUpdateInstallResult {
  const SilentUpdateInstallResult({
    required this.installerPath,
    required this.logPath,
    required this.launcherPath,
    required this.launcherStatusPath,
    required this.installDirectory,
    required this.strategy,
    required this.installDirectoryWritable,
    required this.appPid,
    required this.updateDirectorySecurityStatus,
  });

  final String installerPath;
  final String logPath;
  final String launcherPath;
  final String launcherStatusPath;
  final String installDirectory;
  final SilentUpdateInstallStrategy strategy;
  final bool installDirectoryWritable;
  final int appPid;
  final String updateDirectorySecurityStatus;
}

abstract interface class ISilentUpdateInstaller {
  Future<Result<SilentUpdateInstallResult>> install(
    SilentUpdateInstallRequest request,
  );

  Future<Result<void>> cleanupObsoleteArtifacts();
}
