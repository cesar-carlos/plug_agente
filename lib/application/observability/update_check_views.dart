import 'package:plug_agente/application/observability/update_check_diagnostics.dart';

/// Typed projections of the flat-field [UpdateCheckDiagnostics]. The
/// audit flagged the diagnostics container as a 62-nullable data clump
/// and recommended composing it from smaller value objects. We expose
/// these objects as **views** built from the existing flat fields so:
///
/// - the storage format on disk stays identical (no migration);
/// - the 30+ `copyWith(...)` and persistence call sites keep working;
/// - new readers (Settings UI, support builder, telemetry payloads)
///   can pattern-match on cohesive groups instead of remembering which
///   of the 62 fields belong together.
///
/// The mapping is one-way: each view captures the relevant subset at
/// construction time. To "mutate" a view, mutate the underlying
/// diagnostics via `copyWith(...)` and rebuild the view.

/// Per-cycle context: when/where/who. Always present (no nullability
/// for the fields that are part of the diagnostics constructor's
/// required block, plus the cycle correlation id).
class UpdateCheckContextView {
  const UpdateCheckContextView({
    required this.checkedAt,
    required this.configuredFeedUrl,
    required this.requestedFeedUrl,
    this.checkId,
    this.currentVersion,
  });

  final DateTime checkedAt;
  final String configuredFeedUrl;
  final String requestedFeedUrl;
  final String? checkId;
  final String? currentVersion;
}

/// Timing of the trigger -> completion handshake.
class UpdateCheckTimingView {
  const UpdateCheckTimingView({
    this.probeRequestUrl,
    this.triggerStartedAt,
    this.triggerCompletedAt,
    this.completedAt,
    this.completionSource,
  });

  final String? probeRequestUrl;
  final DateTime? triggerStartedAt;
  final DateTime? triggerCompletedAt;
  final DateTime? completedAt;
  final UpdateCheckCompletionSource? completionSource;

  Duration? get triggerDuration {
    final start = triggerStartedAt;
    final end = triggerCompletedAt;
    if (start == null || end == null) return null;
    return end.difference(start);
  }
}

/// Probe outcome: did the appcast probe succeed, what version did it
/// return, and how does it compare to what Sparkle saw.
class ProbeOutcomeView {
  const ProbeOutcomeView({
    this.succeeded,
    this.version,
    this.os,
    this.itemCount,
    this.errorMessage,
    this.matchesSparkle,
  });

  final bool? succeeded;
  final String? version;
  final String? os;
  final int? itemCount;
  final String? errorMessage;
  final bool? matchesSparkle;
}

/// Asset/remote-version metadata captured from the appcast.
class AssetMetadataView {
  const AssetMetadataView({
    this.remoteVersion,
    this.remoteDisplayVersion,
    this.assetUrl,
    this.assetSize,
    this.assetName,
    this.expectedSha256,
    this.actualSha256,
    this.hashValidationStatus,
    this.releaseNotes,
    this.releaseNotesUrl,
  });

  final String? remoteVersion;
  final String? remoteDisplayVersion;
  final String? assetUrl;
  final int? assetSize;
  final String? assetName;
  final String? expectedSha256;
  final String? actualSha256;
  final String? hashValidationStatus;
  final String? releaseNotes;
  final String? releaseNotesUrl;
}

/// Launcher + installer state, including elevation outcome.
class LauncherSnapshotView {
  const LauncherSnapshotView({
    this.installerPath,
    this.installerLogPath,
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
    this.updateDirectorySecurityStatus,
    this.installDirectoryWritable,
    this.elevatedCancelled,
  });

  final String? installerPath;
  final String? installerLogPath;
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
  final String? updateDirectorySecurityStatus;
  final bool? installDirectoryWritable;
  final bool? elevatedCancelled;
}

/// Authenticode/Ed25519 signature snapshot. Carries both the helper
/// (installer-side) and feed (appcast Ed25519) sub-states so the
/// settings UI can render them side by side without reaching into the
/// flat field list manually.
class SignatureSnapshotView {
  const SignatureSnapshotView({
    this.helperSignatureStatus,
    this.helperSha256,
    this.signatureStatus,
    this.signatureRequired,
    this.feedSignatureStatus,
    this.feedSignatureRequired,
  });

  final String? helperSignatureStatus;
  final String? helperSha256;
  final String? signatureStatus;
  final bool? signatureRequired;
  final String? feedSignatureStatus;
  final bool? feedSignatureRequired;
}

/// Rollout (channel + percentage + bucket) snapshot.
class RolloutSnapshotView {
  const RolloutSnapshotView({
    this.channel,
    this.percentage,
    this.bucket,
    this.eligible,
  });

  final String? channel;
  final int? percentage;
  final int? bucket;
  final bool? eligible;
}

/// Failure cooldown snapshot (counter + breaker deadline).
class CooldownSnapshotView {
  const CooldownSnapshotView({
    this.failureCount,
    this.cooldownUntil,
  });

  final int? failureCount;
  final DateTime? cooldownUntil;
}

/// Free-form error envelope: validation code + human message + the
/// probe-side error message when available.
class DiagnosticErrorView {
  const DiagnosticErrorView({
    this.validationErrorCode,
    this.errorMessage,
    this.probeErrorMessage,
  });

  final String? validationErrorCode;
  final String? errorMessage;
  final String? probeErrorMessage;

  bool get hasAnyError =>
      (validationErrorCode != null && validationErrorCode!.isNotEmpty) ||
      (errorMessage != null && errorMessage!.isNotEmpty) ||
      (probeErrorMessage != null && probeErrorMessage!.isNotEmpty);
}

/// Typed accessors on [UpdateCheckDiagnostics] that hand out the
/// grouped views. Implemented as an extension so the container class
/// stays untouched (zero risk to persistence/`copyWith` semantics) yet
/// new consumers can write `diagnostics.probe.version` instead of
/// `diagnostics.appcastProbeVersion`.
extension UpdateCheckDiagnosticsViews on UpdateCheckDiagnostics {
  UpdateCheckContextView get context => UpdateCheckContextView(
    checkedAt: checkedAt,
    configuredFeedUrl: configuredFeedUrl,
    requestedFeedUrl: requestedFeedUrl,
    checkId: checkId,
    currentVersion: currentVersion,
  );

  UpdateCheckTimingView get timing => UpdateCheckTimingView(
    probeRequestUrl: probeRequestUrl,
    triggerStartedAt: triggerStartedAt,
    triggerCompletedAt: triggerCompletedAt,
    completedAt: completedAt,
    completionSource: completionSource,
  );

  ProbeOutcomeView get probe => ProbeOutcomeView(
    succeeded: probeSucceeded,
    version: appcastProbeVersion,
    os: appcastProbeOs,
    itemCount: appcastProbeItemCount,
    errorMessage: probeErrorMessage,
    matchesSparkle: probeMatchesSparkle,
  );

  AssetMetadataView get asset => AssetMetadataView(
    remoteVersion: remoteVersion,
    remoteDisplayVersion: remoteDisplayVersion,
    assetUrl: assetUrl,
    assetSize: assetSize,
    assetName: assetName,
    expectedSha256: sha256,
    actualSha256: actualSha256,
    hashValidationStatus: hashValidationStatus,
    releaseNotes: releaseNotes,
    releaseNotesUrl: releaseNotesUrl,
  );

  LauncherSnapshotView get launcher => LauncherSnapshotView(
    installerPath: installerPath,
    installerLogPath: installerLogPath,
    installDirectory: installDirectory,
    silentUpdateStrategy: silentUpdateStrategy,
    launcherPath: launcherPath,
    launcherStatusPath: launcherStatusPath,
    launcherState: launcherState,
    nonAdminExitCode: nonAdminExitCode,
    nonAdminDurationMs: nonAdminDurationMs,
    elevatedExitCode: elevatedExitCode,
    elevatedDurationMs: elevatedDurationMs,
    elevatedRetryStarted: elevatedRetryStarted,
    waitForAppExitDurationMs: waitForAppExitDurationMs,
    appPid: appPid,
    updateDirectorySecurityStatus: updateDirectorySecurityStatus,
    installDirectoryWritable: installDirectoryWritable,
    elevatedCancelled: elevatedCancelled,
  );

  SignatureSnapshotView get signature => SignatureSnapshotView(
    helperSignatureStatus: helperSignatureStatus,
    helperSha256: helperSha256,
    signatureStatus: signatureStatus,
    signatureRequired: signatureRequired,
    feedSignatureStatus: feedSignatureStatus,
    feedSignatureRequired: feedSignatureRequired,
  );

  RolloutSnapshotView get rollout => RolloutSnapshotView(
    channel: rolloutChannel,
    percentage: rolloutPercentage,
    bucket: rolloutBucket,
    eligible: rolloutEligible,
  );

  CooldownSnapshotView get cooldown => CooldownSnapshotView(
    failureCount: automaticFailureCount,
    cooldownUntil: automaticCooldownUntil,
  );

  DiagnosticErrorView get errors => DiagnosticErrorView(
    validationErrorCode: validationErrorCode,
    errorMessage: errorMessage,
    probeErrorMessage: probeErrorMessage,
  );
}
