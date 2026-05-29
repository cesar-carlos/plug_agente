enum UpdateCheckCompletionSource {
  updateAvailable,
  updateNotAvailable,
  updaterError,
  triggerTimeout,
  completionTimeout,
  triggerFailure,
  notInitialized,
  circuitOpen,
  automaticDisabled,
  automaticPendingCompleted,
  automaticPendingFailed,
  automaticUpdateNotAvailable,
  automaticValidationFailure,
  automaticDownloadFailure,

  /// Download succeeded and installer + helper are staged on disk. The
  /// agent is still fully connected and operational; only an explicit
  /// apply (user-initiated or natural app close) will trigger the helper
  /// process and the actual install.
  automaticInstallReady,

  /// Probe detected a new version, but the automatic flow stopped before
  /// downloading because Windows UAC would prompt the user for elevation
  /// during install. The operator must confirm via the in-app banner
  /// before the download proceeds; the agent keeps running normally.
  automaticAwaitingUserConsent,

  automaticInstallStarted,
  automaticInstallFailure,
  automaticCooldown,
  automaticRolloutSkipped,

  /// The user disabled automatic silent updates while a check was already in
  /// flight (probe or download). The coordinator honored the cancellation
  /// instead of letting the installer run to completion.
  automaticCancelled,
  automaticQuietHours,
}

class UpdateCheckDiagnostics {
  const UpdateCheckDiagnostics({
    required this.checkedAt,
    required this.configuredFeedUrl,
    required this.requestedFeedUrl,
    this.checkId,
    this.currentVersion,
    this.probeRequestUrl,
    this.triggerStartedAt,
    this.triggerCompletedAt,
    this.completedAt,
    this.completionSource,
    this.probeSucceeded,
    this.appcastProbeVersion,
    this.appcastProbeOs,
    this.appcastProbeItemCount,
    this.updateAvailable,
    this.remoteVersion,
    this.remoteDisplayVersion,
    this.assetUrl,
    this.assetSize,
    this.assetName,
    this.sha256,
    this.actualSha256,
    this.hashValidationStatus,
    this.installerPath,
    this.installerLogPath,
    this.pendingVersion,
    this.installDirectory,
    this.silentUpdateStrategy,
    this.launcherPath,
    this.launcherStatusPath,
    this.launcherState,
    this.nonAdminExitCode,
    this.nonAdminDurationMs,
    this.elevatedExitCode,
    this.elevatedDurationMs,
    this.elevatedRetryStarted,
    this.waitForAppExitDurationMs,
    this.appPid,
    this.signatureStatus,
    this.signatureRequired,
    this.updateDirectorySecurityStatus,
    this.installDirectoryWritable,
    this.elevatedCancelled,
    this.helperSha256,
    this.helperSignatureStatus,
    this.feedSignatureStatus,
    this.feedSignatureRequired,
    this.releaseNotes,
    this.releaseNotesUrl,
    this.rolloutChannel,
    this.rolloutPercentage,
    this.rolloutBucket,
    this.rolloutEligible,
    this.automaticFailureCount,
    this.automaticCooldownUntil,
    this.validationErrorCode,
    this.errorMessage,
    this.probeErrorMessage,
    this.probeMatchesSparkle,
  });

  final DateTime checkedAt;
  final String configuredFeedUrl;
  final String requestedFeedUrl;

  /// Time-ordered UUIDv7 generated at the start of each check (manual,
  /// background, or silent). Lets operators correlate logs, diagnostics and
  /// future telemetry pushes (Fase 7) across boot sessions.
  final String? checkId;

  final String? currentVersion;
  final String? probeRequestUrl;
  final DateTime? triggerStartedAt;
  final DateTime? triggerCompletedAt;
  final DateTime? completedAt;
  final UpdateCheckCompletionSource? completionSource;
  final bool? probeSucceeded;
  final String? appcastProbeVersion;
  final String? appcastProbeOs;
  final int? appcastProbeItemCount;
  final bool? updateAvailable;
  final String? remoteVersion;
  final String? remoteDisplayVersion;
  final String? assetUrl;
  final int? assetSize;
  final String? assetName;
  final String? sha256;
  final String? actualSha256;
  final String? hashValidationStatus;
  final String? installerPath;
  final String? installerLogPath;
  final String? pendingVersion;
  final String? installDirectory;
  final String? silentUpdateStrategy;
  final String? launcherPath;
  final String? launcherStatusPath;
  final String? launcherState;
  final int? nonAdminExitCode;
  final int? nonAdminDurationMs;
  final int? elevatedExitCode;
  final int? elevatedDurationMs;
  final bool? elevatedRetryStarted;
  final int? waitForAppExitDurationMs;
  final int? appPid;
  final String? signatureStatus;
  final bool? signatureRequired;
  final String? updateDirectorySecurityStatus;
  final bool? installDirectoryWritable;
  final bool? elevatedCancelled;

  /// SHA-256 fingerprint of the source `plug_update_helper.exe` that was
  /// copied and launched for this silent update. Diagnostic-only signal that
  /// lets operators compare across installs / detect tampering between
  /// releases. `null` when not measured (e.g., the launcher path was missing
  /// or the install pipeline aborted before the helper copy).
  final String? helperSha256;

  /// Outcome of the Authenticode probe on the source helper executable.
  /// Mirrors `HelperSignatureStatus.name` (`valid`, `invalid`, `unsigned`,
  /// `unknown`). When `requireValidSignature=true` and this is not `valid`,
  /// the installer refuses to launch (validation_code:
  /// `helper_signature_<status>`).
  final String? helperSignatureStatus;

  /// Outcome of the Ed25519 `plug:edSignature` verification on the appcast
  /// enclosure. Mirrors `AppcastSignatureVerificationStatus.name` (`missing`,
  /// `publicKeyUnavailable`, `malformed`, `valid`, `invalid`). `null` when
  /// the probe did not reach the signature step (e.g., probe failed earlier).
  final String? feedSignatureStatus;

  /// Whether the running build requires a valid feed signature for the
  /// silent flow to proceed. Mirrors
  /// `AUTO_UPDATE_REQUIRE_FEED_SIGNATURE`. `null` when the field was
  /// captured before the requirement check ran.
  final bool? feedSignatureRequired;

  /// Release notes captured from the appcast `<description>` element of the
  /// item that won the probe. Optional — publishers can omit it. Rendered
  /// in the Settings UI as a collapsible block; basic sanitisation applies.
  final String? releaseNotes;

  /// External URL to release notes (sparkle:releaseNotesLink). When both
  /// this and [releaseNotes] are present, the UI shows the inline text and
  /// a "more details" link.
  final String? releaseNotesUrl;
  final String? rolloutChannel;
  final int? rolloutPercentage;
  final int? rolloutBucket;
  final bool? rolloutEligible;
  final int? automaticFailureCount;
  final DateTime? automaticCooldownUntil;
  final String? validationErrorCode;
  final String? errorMessage;
  final String? probeErrorMessage;

  /// Whether the version the custom probe found matches the version WinSparkle
  /// reported. `null` when the check did not complete both paths, or when one
  /// of the two versions is unavailable. `false` signals a CDN cache skew.
  final bool? probeMatchesSparkle;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'checkedAt': checkedAt.toIso8601String(),
      'configuredFeedUrl': configuredFeedUrl,
      'requestedFeedUrl': requestedFeedUrl,
      'checkId': checkId,
      'currentVersion': currentVersion,
      'probeRequestUrl': probeRequestUrl,
      'triggerStartedAt': triggerStartedAt?.toIso8601String(),
      'triggerCompletedAt': triggerCompletedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'completionSource': completionSource?.name,
      'probeSucceeded': probeSucceeded,
      'appcastProbeVersion': appcastProbeVersion,
      'appcastProbeOs': appcastProbeOs,
      'appcastProbeItemCount': appcastProbeItemCount,
      'updateAvailable': updateAvailable,
      'remoteVersion': remoteVersion,
      'remoteDisplayVersion': remoteDisplayVersion,
      'assetUrl': assetUrl,
      'assetSize': assetSize,
      'assetName': assetName,
      'sha256': sha256,
      'actualSha256': actualSha256,
      'hashValidationStatus': hashValidationStatus,
      'installerPath': installerPath,
      'installerLogPath': installerLogPath,
      'pendingVersion': pendingVersion,
      'installDirectory': installDirectory,
      'silentUpdateStrategy': silentUpdateStrategy,
      'launcherPath': launcherPath,
      'launcherStatusPath': launcherStatusPath,
      'launcherState': launcherState,
      'nonAdminExitCode': nonAdminExitCode,
      'nonAdminDurationMs': nonAdminDurationMs,
      'elevatedExitCode': elevatedExitCode,
      'elevatedDurationMs': elevatedDurationMs,
      'elevatedRetryStarted': elevatedRetryStarted,
      'waitForAppExitDurationMs': waitForAppExitDurationMs,
      'appPid': appPid,
      'signatureStatus': signatureStatus,
      'signatureRequired': signatureRequired,
      'updateDirectorySecurityStatus': updateDirectorySecurityStatus,
      'installDirectoryWritable': installDirectoryWritable,
      'elevatedCancelled': elevatedCancelled,
      'helperSha256': helperSha256,
      'helperSignatureStatus': helperSignatureStatus,
      'feedSignatureStatus': feedSignatureStatus,
      'feedSignatureRequired': feedSignatureRequired,
      'releaseNotes': releaseNotes,
      'releaseNotesUrl': releaseNotesUrl,
      'rolloutChannel': rolloutChannel,
      'rolloutPercentage': rolloutPercentage,
      'rolloutBucket': rolloutBucket,
      'rolloutEligible': rolloutEligible,
      'automaticFailureCount': automaticFailureCount,
      'automaticCooldownUntil': automaticCooldownUntil?.toIso8601String(),
      'validationErrorCode': validationErrorCode,
      'errorMessage': errorMessage,
      'probeErrorMessage': probeErrorMessage,
      'probeMatchesSparkle': probeMatchesSparkle,
    };
  }

  static UpdateCheckDiagnostics? fromJson(Map<String, dynamic> json) {
    final checkedAtRaw = json['checkedAt'];
    final configuredFeedUrl = json['configuredFeedUrl'];
    final requestedFeedUrl = json['requestedFeedUrl'];
    if (checkedAtRaw is! String || configuredFeedUrl is! String || requestedFeedUrl is! String) {
      return null;
    }

    final checkedAt = DateTime.tryParse(checkedAtRaw);
    if (checkedAt == null) {
      return null;
    }

    return UpdateCheckDiagnostics(
      checkedAt: checkedAt,
      configuredFeedUrl: configuredFeedUrl,
      requestedFeedUrl: requestedFeedUrl,
      checkId: json['checkId'] as String?,
      currentVersion: json['currentVersion'] as String?,
      probeRequestUrl: json['probeRequestUrl'] as String?,
      triggerStartedAt: _parseDateTime(json['triggerStartedAt']),
      triggerCompletedAt: _parseDateTime(json['triggerCompletedAt']),
      completedAt: _parseDateTime(json['completedAt']),
      completionSource: _parseCompletionSource(json['completionSource']),
      probeSucceeded: json['probeSucceeded'] as bool?,
      appcastProbeVersion: json['appcastProbeVersion'] as String?,
      appcastProbeOs: json['appcastProbeOs'] as String?,
      appcastProbeItemCount: _parseInt(json['appcastProbeItemCount']),
      updateAvailable: json['updateAvailable'] as bool?,
      remoteVersion: json['remoteVersion'] as String?,
      remoteDisplayVersion: json['remoteDisplayVersion'] as String?,
      assetUrl: json['assetUrl'] as String?,
      assetSize: _parseInt(json['assetSize']),
      assetName: json['assetName'] as String?,
      sha256: json['sha256'] as String?,
      actualSha256: json['actualSha256'] as String?,
      hashValidationStatus: json['hashValidationStatus'] as String?,
      installerPath: json['installerPath'] as String?,
      installerLogPath: json['installerLogPath'] as String?,
      pendingVersion: json['pendingVersion'] as String?,
      installDirectory: json['installDirectory'] as String?,
      silentUpdateStrategy: json['silentUpdateStrategy'] as String?,
      launcherPath: json['launcherPath'] as String?,
      launcherStatusPath: json['launcherStatusPath'] as String?,
      launcherState: json['launcherState'] as String?,
      nonAdminExitCode: _parseInt(json['nonAdminExitCode']),
      nonAdminDurationMs: _parseInt(json['nonAdminDurationMs']),
      elevatedExitCode: _parseInt(json['elevatedExitCode']),
      elevatedDurationMs: _parseInt(json['elevatedDurationMs']),
      elevatedRetryStarted: json['elevatedRetryStarted'] as bool?,
      waitForAppExitDurationMs: _parseInt(json['waitForAppExitDurationMs']),
      appPid: _parseInt(json['appPid']),
      signatureStatus: json['signatureStatus'] as String?,
      signatureRequired: json['signatureRequired'] as bool?,
      updateDirectorySecurityStatus: json['updateDirectorySecurityStatus'] as String?,
      installDirectoryWritable: json['installDirectoryWritable'] as bool?,
      elevatedCancelled: json['elevatedCancelled'] as bool?,
      helperSha256: json['helperSha256'] as String?,
      helperSignatureStatus: json['helperSignatureStatus'] as String?,
      feedSignatureStatus: json['feedSignatureStatus'] as String?,
      feedSignatureRequired: json['feedSignatureRequired'] as bool?,
      releaseNotes: json['releaseNotes'] as String?,
      releaseNotesUrl: json['releaseNotesUrl'] as String?,
      rolloutChannel: json['rolloutChannel'] as String?,
      rolloutPercentage: _parseInt(json['rolloutPercentage']),
      rolloutBucket: _parseInt(json['rolloutBucket']),
      rolloutEligible: json['rolloutEligible'] as bool?,
      automaticFailureCount: _parseInt(json['automaticFailureCount']),
      automaticCooldownUntil: _parseDateTime(json['automaticCooldownUntil']),
      validationErrorCode: json['validationErrorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      probeErrorMessage: json['probeErrorMessage'] as String?,
      probeMatchesSparkle: json['probeMatchesSparkle'] as bool?,
    );
  }

  UpdateCheckDiagnostics copyWith({
    DateTime? checkedAt,
    String? configuredFeedUrl,
    String? requestedFeedUrl,
    String? checkId,
    String? currentVersion,
    String? probeRequestUrl,
    DateTime? triggerStartedAt,
    DateTime? triggerCompletedAt,
    DateTime? completedAt,
    UpdateCheckCompletionSource? completionSource,
    bool? probeSucceeded,
    String? appcastProbeVersion,
    String? appcastProbeOs,
    int? appcastProbeItemCount,
    bool? updateAvailable,
    String? remoteVersion,
    String? remoteDisplayVersion,
    String? assetUrl,
    int? assetSize,
    String? assetName,
    String? sha256,
    String? actualSha256,
    String? hashValidationStatus,
    String? installerPath,
    String? installerLogPath,
    String? pendingVersion,
    String? installDirectory,
    String? silentUpdateStrategy,
    String? launcherPath,
    String? launcherStatusPath,
    String? launcherState,
    int? nonAdminExitCode,
    int? nonAdminDurationMs,
    int? elevatedExitCode,
    int? elevatedDurationMs,
    bool? elevatedRetryStarted,
    int? waitForAppExitDurationMs,
    int? appPid,
    String? signatureStatus,
    bool? signatureRequired,
    String? updateDirectorySecurityStatus,
    bool? installDirectoryWritable,
    bool? elevatedCancelled,
    String? helperSha256,
    String? helperSignatureStatus,
    String? feedSignatureStatus,
    bool? feedSignatureRequired,
    String? releaseNotes,
    String? releaseNotesUrl,
    String? rolloutChannel,
    int? rolloutPercentage,
    int? rolloutBucket,
    bool? rolloutEligible,
    int? automaticFailureCount,
    DateTime? automaticCooldownUntil,
    String? validationErrorCode,
    String? errorMessage,
    String? probeErrorMessage,
    bool? probeMatchesSparkle,
  }) {
    return UpdateCheckDiagnostics(
      checkedAt: checkedAt ?? this.checkedAt,
      configuredFeedUrl: configuredFeedUrl ?? this.configuredFeedUrl,
      requestedFeedUrl: requestedFeedUrl ?? this.requestedFeedUrl,
      checkId: checkId ?? this.checkId,
      currentVersion: currentVersion ?? this.currentVersion,
      probeRequestUrl: probeRequestUrl ?? this.probeRequestUrl,
      triggerStartedAt: triggerStartedAt ?? this.triggerStartedAt,
      triggerCompletedAt: triggerCompletedAt ?? this.triggerCompletedAt,
      completedAt: completedAt ?? this.completedAt,
      completionSource: completionSource ?? this.completionSource,
      probeSucceeded: probeSucceeded ?? this.probeSucceeded,
      appcastProbeVersion: appcastProbeVersion ?? this.appcastProbeVersion,
      appcastProbeOs: appcastProbeOs ?? this.appcastProbeOs,
      appcastProbeItemCount: appcastProbeItemCount ?? this.appcastProbeItemCount,
      updateAvailable: updateAvailable ?? this.updateAvailable,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      remoteDisplayVersion: remoteDisplayVersion ?? this.remoteDisplayVersion,
      assetUrl: assetUrl ?? this.assetUrl,
      assetSize: assetSize ?? this.assetSize,
      assetName: assetName ?? this.assetName,
      sha256: sha256 ?? this.sha256,
      actualSha256: actualSha256 ?? this.actualSha256,
      hashValidationStatus: hashValidationStatus ?? this.hashValidationStatus,
      installerPath: installerPath ?? this.installerPath,
      installerLogPath: installerLogPath ?? this.installerLogPath,
      pendingVersion: pendingVersion ?? this.pendingVersion,
      installDirectory: installDirectory ?? this.installDirectory,
      silentUpdateStrategy: silentUpdateStrategy ?? this.silentUpdateStrategy,
      launcherPath: launcherPath ?? this.launcherPath,
      launcherStatusPath: launcherStatusPath ?? this.launcherStatusPath,
      launcherState: launcherState ?? this.launcherState,
      nonAdminExitCode: nonAdminExitCode ?? this.nonAdminExitCode,
      nonAdminDurationMs: nonAdminDurationMs ?? this.nonAdminDurationMs,
      elevatedExitCode: elevatedExitCode ?? this.elevatedExitCode,
      elevatedDurationMs: elevatedDurationMs ?? this.elevatedDurationMs,
      elevatedRetryStarted: elevatedRetryStarted ?? this.elevatedRetryStarted,
      waitForAppExitDurationMs: waitForAppExitDurationMs ?? this.waitForAppExitDurationMs,
      appPid: appPid ?? this.appPid,
      signatureStatus: signatureStatus ?? this.signatureStatus,
      signatureRequired: signatureRequired ?? this.signatureRequired,
      updateDirectorySecurityStatus: updateDirectorySecurityStatus ?? this.updateDirectorySecurityStatus,
      installDirectoryWritable: installDirectoryWritable ?? this.installDirectoryWritable,
      elevatedCancelled: elevatedCancelled ?? this.elevatedCancelled,
      helperSha256: helperSha256 ?? this.helperSha256,
      helperSignatureStatus: helperSignatureStatus ?? this.helperSignatureStatus,
      feedSignatureStatus: feedSignatureStatus ?? this.feedSignatureStatus,
      feedSignatureRequired: feedSignatureRequired ?? this.feedSignatureRequired,
      releaseNotes: releaseNotes ?? this.releaseNotes,
      releaseNotesUrl: releaseNotesUrl ?? this.releaseNotesUrl,
      rolloutChannel: rolloutChannel ?? this.rolloutChannel,
      rolloutPercentage: rolloutPercentage ?? this.rolloutPercentage,
      rolloutBucket: rolloutBucket ?? this.rolloutBucket,
      rolloutEligible: rolloutEligible ?? this.rolloutEligible,
      automaticFailureCount: automaticFailureCount ?? this.automaticFailureCount,
      automaticCooldownUntil: automaticCooldownUntil ?? this.automaticCooldownUntil,
      validationErrorCode: validationErrorCode ?? this.validationErrorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      probeErrorMessage: probeErrorMessage ?? this.probeErrorMessage,
      probeMatchesSparkle: probeMatchesSparkle ?? this.probeMatchesSparkle,
    );
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static UpdateCheckCompletionSource? _parseCompletionSource(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    for (final source in UpdateCheckCompletionSource.values) {
      if (source.name == value) {
        return source;
      }
    }
    return null;
  }
}
