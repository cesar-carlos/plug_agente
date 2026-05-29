/// Sealed representation of an in-flight or staged silent update record.
///
/// Replaces the old single class with 15 nullables (where readers had to
/// guard "is this a probe stub, a stale record or a ready-to-launch
/// install?" via long null-checks). Variants:
///
/// - [PendingSilentUpdateProbed]: the coordinator persisted the record
///   *before* calling the installer. Carries only the version + start
///   timestamp; if the process restarts after this point but before the
///   download finishes, the reconciler treats it as stale.
/// - [PendingSilentUpdateDownloaded]: the installer finished staging the
///   helper + setup on disk. Carries every path needed by
///   `ISilentUpdateInstaller.launchPreparedHelper` so the apply can resume
///   even after a process restart.
sealed class PendingSilentUpdate {
  const PendingSilentUpdate({
    required this.version,
    required this.startedAt,
  });

  final String version;

  /// May be `null` when the persisted record came from an older agent
  /// build that did not stamp the start time. Readers (e.g. the
  /// reconciler's "should we keep this pending?" gate) must treat null
  /// as "no recent activity" and time out the record on the next cycle,
  /// instead of re-stamping to `DateTime.now()` and keeping it alive
  /// forever.
  final DateTime? startedAt;

  Map<String, Object?> toJson();

  static PendingSilentUpdate? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! String || version.isEmpty) return null;
    final startedAt = _readDateTime(json['startedAt']);
    // Presence of `installerPath` AND `launcherPath` AND `appPid` is the
    // canonical signal that the staged path is complete enough to apply.
    final installerPath = json['installerPath'] as String?;
    final launcherPath = json['launcherPath'] as String?;
    final logPath = json['logPath'] as String?;
    final launcherStatusPath = json['launcherStatusPath'] as String?;
    final installDirectory = json['installDirectory'] as String?;
    final assetSize = _readInt(json['assetSize']);
    final sha256 = json['sha256'] as String?;
    final installDirectoryWritable = json['installDirectoryWritable'] as bool?;
    final requireValidSignature = json['requireValidSignature'] as bool?;
    final appPid = _readInt(json['appPid']);
    final strategy = json['strategy'] as String?;
    final updateDirectorySecurityStatus = json['updateDirectorySecurityStatus'] as String?;

    // "Downloaded" means the installer + helper paths are persisted so
    // a future cycle can re-launch the helper. The extra fields needed
    // by `applyPendingDownloadedUpdate` (assetSize/sha256/etc.) may be
    // missing on records written by older agent builds; we keep them
    // nullable here for backward compatibility and re-validate at apply
    // time inside the coordinator.
    final hasStagedPayload =
        installerPath != null &&
        launcherPath != null &&
        logPath != null &&
        launcherStatusPath != null &&
        installDirectory != null &&
        appPid != null;

    if (hasStagedPayload) {
      return PendingSilentUpdateDownloaded(
        version: version,
        startedAt: startedAt,
        installerPath: installerPath,
        logPath: logPath,
        launcherPath: launcherPath,
        launcherStatusPath: launcherStatusPath,
        installDirectory: installDirectory,
        strategy: strategy,
        assetSize: assetSize,
        sha256: sha256,
        installDirectoryWritable: installDirectoryWritable,
        requireValidSignature: requireValidSignature,
        appPid: appPid,
        updateDirectorySecurityStatus: updateDirectorySecurityStatus,
      );
    }

    return PendingSilentUpdateProbed(
      version: version,
      startedAt: startedAt,
    );
  }
}

/// Pre-download marker. Persisted by the coordinator the instant a probe
/// returns a newer version and before it calls `installer.install(...)`.
/// If we crash here, the reconciler classifies it as stale and clears.
final class PendingSilentUpdateProbed extends PendingSilentUpdate {
  const PendingSilentUpdateProbed({
    required super.version,
    required super.startedAt,
  });

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'startedAt': startedAt?.toIso8601String(),
  };
}

/// Post-download record. The installer finished staging the bytes and the
/// helper EXE; we have every input needed to launch the helper later,
/// even after a process restart.
final class PendingSilentUpdateDownloaded extends PendingSilentUpdate {
  const PendingSilentUpdateDownloaded({
    required super.version,
    required super.startedAt,
    required this.installerPath,
    required this.logPath,
    required this.launcherPath,
    required this.launcherStatusPath,
    required this.installDirectory,
    required this.appPid,
    this.assetSize,
    this.sha256,
    this.installDirectoryWritable,
    this.requireValidSignature,
    this.strategy,
    this.updateDirectorySecurityStatus,
  });

  final String installerPath;
  final String logPath;
  final String launcherPath;
  final String launcherStatusPath;
  final String installDirectory;
  final int appPid;

  /// Fields below are nullable because older agent builds persisted a
  /// pending record without them. The coordinator must validate them
  /// before invoking `applyPendingDownloadedUpdate`; missing values
  /// surface a typed failure instead of crashing.
  final int? assetSize;
  final String? sha256;
  final bool? installDirectoryWritable;
  final bool? requireValidSignature;
  final String? strategy;
  final String? updateDirectorySecurityStatus;

  /// Convenience flag used by the coordinator to decide whether the
  /// record carries every field needed to launch the helper without an
  /// extra round-trip.
  bool get hasFullApplyMetadata =>
      assetSize != null && sha256 != null && installDirectoryWritable != null && requireValidSignature != null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'startedAt': startedAt?.toIso8601String(),
    'installerPath': installerPath,
    'logPath': logPath,
    'launcherPath': launcherPath,
    'launcherStatusPath': launcherStatusPath,
    'installDirectory': installDirectory,
    'strategy': strategy,
    'assetSize': assetSize,
    'sha256': sha256,
    'installDirectoryWritable': installDirectoryWritable,
    'requireValidSignature': requireValidSignature,
    'appPid': appPid,
    'updateDirectorySecurityStatus': updateDirectorySecurityStatus,
  };
}

/// Snapshot of the launcher status file written by the external helper.
/// Lives next to the pending record so the coordinator can rebuild
/// diagnostics across boots.
class SilentUpdateLauncherStatus {
  const SilentUpdateLauncherStatus({
    required this.state,
    required this.strategy,
    required this.installDirectory,
    required this.installerPath,
    required this.logPath,
    required this.nonAdminExitCode,
    required this.nonAdminDurationMs,
    required this.elevatedExitCode,
    required this.elevatedDurationMs,
    required this.elevatedRetryStarted,
    required this.waitForAppExitDurationMs,
    required this.appPid,
    required this.signatureStatus,
    required this.signatureRequired,
    required this.actualSha256,
    required this.hashValidationStatus,
    required this.installDirectoryWritable,
    required this.elevatedCancelled,
    required this.errorMessage,
    required this.lastUpdatedAt,
  });

  final String? state;
  final String? strategy;
  final String? installDirectory;
  final String? installerPath;
  final String? logPath;
  final int? nonAdminExitCode;
  final int? nonAdminDurationMs;
  final int? elevatedExitCode;
  final int? elevatedDurationMs;
  final bool? elevatedRetryStarted;
  final int? waitForAppExitDurationMs;
  final int? appPid;
  final String? signatureStatus;
  final bool? signatureRequired;
  final String? actualSha256;
  final String? hashValidationStatus;
  final bool? installDirectoryWritable;
  final bool? elevatedCancelled;
  final String? errorMessage;
  final DateTime? lastUpdatedAt;

  String? get failureMessage {
    final error = errorMessage;
    if (error != null && error.isNotEmpty) return error;
    final stateLabel = state;
    if (stateLabel != null && stateLabel.isNotEmpty) {
      return 'Launcher status: $stateLabel';
    }
    return null;
  }

  static SilentUpdateLauncherStatus fromJson(Map<String, dynamic> json) {
    return SilentUpdateLauncherStatus(
      state: json['state'] as String?,
      strategy: json['strategy'] as String?,
      installDirectory: json['installDirectory'] as String?,
      installerPath: json['installerPath'] as String?,
      logPath: json['logPath'] as String?,
      nonAdminExitCode: _readInt(json['nonAdminExitCode']),
      nonAdminDurationMs: _readInt(json['nonAdminDurationMs']),
      elevatedExitCode: _readInt(json['elevatedExitCode']),
      elevatedDurationMs: _readInt(json['elevatedDurationMs']),
      elevatedRetryStarted: json['elevatedRetryStarted'] as bool?,
      waitForAppExitDurationMs: _readInt(json['waitForAppExitDurationMs']),
      appPid: _readInt(json['appPid']),
      signatureStatus: json['signatureStatus'] as String?,
      signatureRequired: json['signatureRequired'] as bool?,
      actualSha256: json['actualSha256'] as String?,
      hashValidationStatus: json['hashValidationStatus'] as String?,
      installDirectoryWritable: json['installDirectoryWritable'] as bool?,
      elevatedCancelled: json['elevatedCancelled'] as bool?,
      errorMessage: json['errorMessage'] as String?,
      lastUpdatedAt: _readDateTime(json['lastUpdatedAt']),
    );
  }
}

int? _readInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

DateTime? _readDateTime(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}
