import 'package:plug_agente/domain/errors/silent_install_failure.dart';
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
    this.allowDownloadResume = true,
    this.deferHelperLaunch = false,
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

  /// When `true` (default) the installer keeps a partial `.part` file across
  /// attempts and asks the server for `Range: bytes=<offset>-` to continue
  /// from where the previous attempt stopped. Set to `false` to force the
  /// classic "always download from zero" path (e.g., when a proxy is known
  /// to mishandle `Range`).
  final bool allowDownloadResume;

  /// When `true`, `install()` downloads and validates the installer + helper
  /// but does **not** launch the helper process. The returned
  /// [SilentUpdateInstallResult] still carries every path needed to launch
  /// the helper later via [ISilentUpdateInstaller.launchPreparedHelper]. The
  /// silent update flow uses this so the agent can keep running normally
  /// after the download; the helper is only launched when the user
  /// explicitly applies the update or the app is closing naturally.
  final bool deferHelperLaunch;

  /// Marker used in failure context so the coordinator can distinguish a
  /// user-driven cancellation from genuine network/validation errors.
  ///
  /// Prefer `failure is SilentInstallCancellationFailure` in new code;
  /// this key is kept for backward compatibility with operators reading
  /// the persisted diagnostics payload.
  static const String cancellationContextKey = SilentInstallFailureContext.cancellationKey;
}

/// Inputs required to launch a previously prepared silent update helper.
///
/// Built from a [SilentUpdateInstallResult] that came back from a prior
/// `install(deferHelperLaunch: true)` invocation. Carrying these as an
/// explicit value object keeps the apply step independent of the in-memory
/// state of the coordinator: even after a process restart, the persisted
/// pending record can rebuild this request and resume the apply.
class SilentUpdateLaunchRequest {
  const SilentUpdateLaunchRequest({
    required this.version,
    required this.installerPath,
    required this.logPath,
    required this.launcherPath,
    required this.launcherStatusPath,
    required this.installDirectory,
    required this.assetSize,
    required this.sha256,
    required this.installDirectoryWritable,
    required this.requireValidSignature,
    required this.appPid,
  });

  final String version;
  final String installerPath;
  final String logPath;
  final String launcherPath;
  final String launcherStatusPath;
  final String installDirectory;
  final int assetSize;
  final String sha256;
  final bool installDirectoryWritable;
  final bool requireValidSignature;
  final int appPid;
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
    this.helperSignatureStatus,
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

  /// Authenticode signature status of the source `plug_update_helper.exe`,
  /// captured via `Get-AuthenticodeSignature` before the helper is copied
  /// to the updates directory. Mirrors `HelperSignatureStatus.name`
  /// (`valid`, `invalid`, `unsigned`, `unknown`). `null` when the probe was
  /// not invoked.
  final String? helperSignatureStatus;
}

abstract interface class ISilentUpdateInstaller {
  Future<Result<SilentUpdateInstallResult>> install(
    SilentUpdateInstallRequest request,
  );

  /// Launches the helper for a previously prepared install (i.e. one that
  /// ran `install()` with [SilentUpdateInstallRequest.deferHelperLaunch] set
  /// to `true`). The helper waits for the app to exit, runs the installer,
  /// and relaunches the agent. The caller must initiate the app close right
  /// after this returns success — the helper's PID-wait window is short.
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request);

  Future<Result<void>> cleanupObsoleteArtifacts();
}
