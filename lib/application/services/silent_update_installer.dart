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
    this.cancelRequested,
  });

  final String version;
  final String assetUrl;
  final int assetSize;
  final String assetName;
  final String sha256;
  final bool requireValidSignature;

  /// Optional cancellation token. When provided and returns `true`, the
  /// installer aborts at the next safe checkpoint (between download chunks,
  /// before launching the helper) without leaving the .part file behind.
  /// Used by the coordinator to honor "user disabled automatic silent updates
  /// mid-download" requests promptly instead of finishing the install.
  final bool Function()? cancelRequested;

  /// Marker used in failure context so the coordinator can distinguish a
  /// user-driven cancellation from genuine network/validation errors.
  static const String cancellationContextKey = 'cancelled';
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
    this.helperSha256,
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

  /// SHA-256 of the source `plug_update_helper.exe` measured at launch time.
  /// Provides a fingerprint for diagnostics so operators can compare across
  /// installs and detect tampering between releases. `null` when measurement
  /// failed (e.g., file disappeared between resolution and copy).
  final String? helperSha256;
}

abstract interface class ISilentUpdateInstaller {
  Future<Result<SilentUpdateInstallResult>> install(
    SilentUpdateInstallRequest request,
  );

  Future<Result<void>> cleanupObsoleteArtifacts();
}
