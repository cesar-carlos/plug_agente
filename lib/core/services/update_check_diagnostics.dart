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
  automaticInstallStarted,
  automaticInstallFailure,
  automaticCooldown,
  automaticRolloutSkipped,
}

class UpdateCheckDiagnostics {
  const UpdateCheckDiagnostics({
    required this.checkedAt,
    required this.configuredFeedUrl,
    required this.requestedFeedUrl,
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
    this.rolloutChannel,
    this.rolloutPercentage,
    this.rolloutBucket,
    this.rolloutEligible,
    this.automaticFailureCount,
    this.automaticCooldownUntil,
    this.validationErrorCode,
    this.errorMessage,
    this.probeErrorMessage,
  });

  final DateTime checkedAt;
  final String configuredFeedUrl;
  final String requestedFeedUrl;
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
  final String? rolloutChannel;
  final int? rolloutPercentage;
  final int? rolloutBucket;
  final bool? rolloutEligible;
  final int? automaticFailureCount;
  final DateTime? automaticCooldownUntil;
  final String? validationErrorCode;
  final String? errorMessage;
  final String? probeErrorMessage;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'checkedAt': checkedAt.toIso8601String(),
      'configuredFeedUrl': configuredFeedUrl,
      'requestedFeedUrl': requestedFeedUrl,
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
      'rolloutChannel': rolloutChannel,
      'rolloutPercentage': rolloutPercentage,
      'rolloutBucket': rolloutBucket,
      'rolloutEligible': rolloutEligible,
      'automaticFailureCount': automaticFailureCount,
      'automaticCooldownUntil': automaticCooldownUntil?.toIso8601String(),
      'validationErrorCode': validationErrorCode,
      'errorMessage': errorMessage,
      'probeErrorMessage': probeErrorMessage,
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
      rolloutChannel: json['rolloutChannel'] as String?,
      rolloutPercentage: _parseInt(json['rolloutPercentage']),
      rolloutBucket: _parseInt(json['rolloutBucket']),
      rolloutEligible: json['rolloutEligible'] as bool?,
      automaticFailureCount: _parseInt(json['automaticFailureCount']),
      automaticCooldownUntil: _parseDateTime(json['automaticCooldownUntil']),
      validationErrorCode: json['validationErrorCode'] as String?,
      errorMessage: json['errorMessage'] as String?,
      probeErrorMessage: json['probeErrorMessage'] as String?,
    );
  }

  UpdateCheckDiagnostics copyWith({
    DateTime? checkedAt,
    String? configuredFeedUrl,
    String? requestedFeedUrl,
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
    String? rolloutChannel,
    int? rolloutPercentage,
    int? rolloutBucket,
    bool? rolloutEligible,
    int? automaticFailureCount,
    DateTime? automaticCooldownUntil,
    String? validationErrorCode,
    String? errorMessage,
    String? probeErrorMessage,
  }) {
    return UpdateCheckDiagnostics(
      checkedAt: checkedAt ?? this.checkedAt,
      configuredFeedUrl: configuredFeedUrl ?? this.configuredFeedUrl,
      requestedFeedUrl: requestedFeedUrl ?? this.requestedFeedUrl,
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
      rolloutChannel: rolloutChannel ?? this.rolloutChannel,
      rolloutPercentage: rolloutPercentage ?? this.rolloutPercentage,
      rolloutBucket: rolloutBucket ?? this.rolloutBucket,
      rolloutEligible: rolloutEligible ?? this.rolloutEligible,
      automaticFailureCount: automaticFailureCount ?? this.automaticFailureCount,
      automaticCooldownUntil: automaticCooldownUntil ?? this.automaticCooldownUntil,
      validationErrorCode: validationErrorCode ?? this.validationErrorCode,
      errorMessage: errorMessage ?? this.errorMessage,
      probeErrorMessage: probeErrorMessage ?? this.probeErrorMessage,
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
