import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';
import 'dart:ui' show VoidCallback;

import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/services/update_check_id_recorder.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_auto_update_metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class ISilentUpdateCoordinator {
  bool get isSilentCheckInProgress;
  bool get automaticSilentUpdatesEnabled;
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics;

  /// True when a silent download finished and the installer is staged on
  /// disk awaiting an explicit apply. The agent stays fully connected and
  /// operational while this is `true`.
  bool get hasPendingDownloadedUpdate;

  void hydratePersistedDiagnostics();

  /// Reconciles any pending install from a previous session, then schedules
  /// the periodic silent check timer when automatic silent updates are enabled.
  Future<void> reconcilePendingAndSchedule();

  /// Triggers the silent cycle (probe → validation → download → stage).
  /// The success bucket carries a [SilentUpdateOutcome] discriminating the
  /// reason the cycle ended (installer ready, no new version, rollout
  /// skipped, cooldown, disabled, cancelled, pending in progress, already
  /// in progress).
  ///
  /// The cycle never closes the app on its own anymore: when a new version
  /// is downloaded the outcome is [SilentUpdateOutcome.installerReady] and
  /// the agent keeps running normally until [applyPendingDownloadedUpdate]
  /// is invoked.
  ///
  /// When Windows UAC is enabled and the current process is not running
  /// elevated, the automatic flow (default `userInitiated: false`) stops
  /// after probing the appcast and surfaces a new
  /// [SilentUpdateOutcome.requiresUserConsent] outcome without downloading.
  /// Pass `userInitiated: true` from the UI banner so the operator's
  /// explicit click bypasses the UAC gate and runs the full download +
  /// stage cycle.
  Future<Result<SilentUpdateOutcome>> checkSilently({bool userInitiated = false});

  /// Launches the staged update helper for a previously downloaded install
  /// and triggers the application close so the helper can run the
  /// installer. No-op (returns `Failure`) when no prepared install exists.
  ///
  /// [noticeTitle] and [noticeBody] override the toast notification shown
  /// during the pre-close grace period when supplied. Pass localized
  /// strings from the UI; defaults are kept for callers without a
  /// localization context.
  ///
  /// When [triggerAppClose] is `false`, the helper is launched but the
  /// close callback is **not** invoked. Use this from the natural app
  /// shutdown path, where the caller is already running the shutdown
  /// sequence and only needs the helper to PID-watch this process.
  /// Calling with `triggerAppClose: true` (the default) from within a
  /// shutdown handler would re-enter the close logic and recurse.
  Future<Result<void>> applyPendingDownloadedUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  });

  /// Starts or restarts the periodic timer and runs an immediate check.
  void scheduleAndStart();

  /// Cancels the periodic timer without touching persisted state.
  void stop();

  /// Asks the coordinator to abort the in-flight silent check at the next
  /// safe checkpoint (between download chunks, before launching the helper).
  /// No-op when no check is running. The coordinator clears its cancel flag
  /// at the beginning of the next [checkSilently] invocation.
  void requestCancellation();

  Future<void> resetFailureCooldownIfNeeded();
}

/// Signature for the callback that flips the app off the tray and exits the
/// process so the prepared helper can install the new version. The optional
/// [noticeTitle] / [noticeBody] are forwarded to the OS toast so the user
/// gets a final on-screen warning before the close, even if the in-app
/// dialog was dismissed.
typedef CloseApplicationForSilentUpdate = Future<void> Function({String? noticeTitle, String? noticeBody});

class SilentUpdateCoordinator implements ISilentUpdateCoordinator {
  SilentUpdateCoordinator(
    this._capabilities,
    this._feedUrlResolver, {
    IAppcastProbeService appcastProbeService = const AppcastProbeService(),
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
    CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
    VoidCallback? onDiagnosticsChanged,
    int automaticFailureCooldownThreshold = _defaultAutomaticFailureCooldownThreshold,
    Duration automaticFailureCooldown = _defaultAutomaticFailureCooldown,
    Duration helperWaitDuration = _defaultHelperWaitDuration,
    Duration Function()? bootJitterProvider,
    IAppcastSignatureVerifier? signatureVerifier,
    UpdateCheckIdRecorder? checkIdRecorder,
    IAutoUpdateMetricsCollector? metricsCollector,
    IUacDetector? uacDetector,
  }) : _appcastProbeService = appcastProbeService,
       _silentUpdateInstaller = silentUpdateInstaller,
       _settingsStore = settingsStore,
       _closeApplicationForSilentUpdate = closeApplicationForSilentUpdate,
       _onDiagnosticsChanged = onDiagnosticsChanged,
       _automaticFailureCooldownThreshold = automaticFailureCooldownThreshold,
       _automaticFailureCooldown = automaticFailureCooldown,
       _helperWaitDuration = helperWaitDuration,
       _bootJitterProvider = bootJitterProvider,
       _signatureVerifier = signatureVerifier ?? Ed25519AppcastSignatureVerifier(),
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(settingsStore: settingsStore),
       _metricsCollector = metricsCollector,
       _uacDetector = uacDetector ?? const NoopUacDetector() {
    hydratePersistedDiagnostics();
  }

  final RuntimeCapabilities _capabilities;

  /// Returns the current resolved feed URL, or `null` when not configured.
  final String? Function() _feedUrlResolver;
  final IAppcastProbeService _appcastProbeService;
  final ISilentUpdateInstaller? _silentUpdateInstaller;
  final IAppSettingsStore? _settingsStore;
  final CloseApplicationForSilentUpdate? _closeApplicationForSilentUpdate;
  final VoidCallback? _onDiagnosticsChanged;
  final int _automaticFailureCooldownThreshold;
  final Duration _automaticFailureCooldown;
  final Duration _helperWaitDuration;

  /// Optional jitter applied to the first automatic check after the timer is
  /// scheduled. Avoids a thundering herd of clients hitting the feed during
  /// fleet restarts. `null` keeps the original "run immediately" behavior.
  final Duration Function()? _bootJitterProvider;

  /// Ed25519 verifier for `plug:edSignature`. Default is the pure-Dart
  /// implementation; tests can inject a deterministic fake.
  final IAppcastSignatureVerifier _signatureVerifier;

  /// Generates UUIDv7 correlation IDs for each silent cycle and keeps a
  /// ring buffer of recent IDs for offline log correlation.
  final UpdateCheckIdRecorder _checkIdRecorder;

  /// Optional metrics sink for probe/download duration histograms. `null`
  /// disables sampling (tests / minimal DI).
  final IAutoUpdateMetricsCollector? _metricsCollector;

  /// Detects whether applying an update would trigger a UAC prompt.
  /// Defaults to a no-op when not configured (test/non-Windows). The
  /// automatic flow honours the detector; manual / user-initiated checks
  /// bypass it because the operator has already consented to the
  /// upcoming UAC prompt by clicking "Install".
  final IUacDetector _uacDetector;

  bool _isSilentCheckInProgress = false;
  bool _cancelRequested = false;
  Timer? _automaticCheckTimer;
  UpdateCheckDiagnostics? _lastAutomaticDiagnostics;

  /// Set at the start of every silent cycle (`checkSilently` /
  /// `_reconcilePendingSilentUpdate`) and propagated to all
  /// `UpdateCheckDiagnostics` constructed during that cycle.
  String? _currentCheckId;

  // Settings keys — same string values as before for backward compatibility.
  static const String _lastAutomaticDiagnosticsKey = 'auto_update.last_automatic_diagnostics';
  static const String _pendingSilentUpdateKey = 'auto_update.pending_silent_update';
  static const String _automaticFailureCountKey = 'auto_update.automatic_failure_count';
  static const String _automaticCooldownUntilKey = 'auto_update.automatic_cooldown_until_ms';
  static const String _automaticRolloutBucketKey = 'auto_update.rollout_bucket';

  static const int _defaultAutomaticFailureCooldownThreshold = 3;
  static const Duration _defaultAutomaticFailureCooldown = Duration(hours: 6);
  static const Duration _defaultHelperWaitDuration = Duration(minutes: 30);

  // Public aliases so other classes (e.g. AutoUpdateOrchestrator) can use the
  // same defaults without hard-coding magic values.
  static const int defaultAutomaticFailureCooldownThreshold = _defaultAutomaticFailureCooldownThreshold;
  static const Duration defaultAutomaticFailureCooldown = _defaultAutomaticFailureCooldown;
  static const Duration defaultHelperWaitDuration = _defaultHelperWaitDuration;

  // ---------------------------------------------------------------------------
  // Public interface
  // ---------------------------------------------------------------------------

  @override
  bool get isSilentCheckInProgress => _isSilentCheckInProgress;

  @override
  bool get automaticSilentUpdatesEnabled =>
      _settingsStore?.getBool(AppSettingsKeys.automaticSilentUpdatesEnabled) ?? true;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => _lastAutomaticDiagnostics;

  @override
  void hydratePersistedDiagnostics() {
    final raw = _settingsStore?.getString(_lastAutomaticDiagnosticsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final restored = UpdateCheckDiagnostics.fromJson(decoded);
        if (restored != null) {
          _lastAutomaticDiagnostics = _reconcileStaleAwaitingConsent(restored);
        }
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse persisted automatic silent update diagnostics',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Drops the [UpdateCheckCompletionSource.automaticAwaitingUserConsent]
  /// completion source when the persisted `pendingVersion` is already
  /// equal to or older than the running build. This guards against
  /// out-of-band updates (e.g., the operator ran the installer manually
  /// after the gate blocked the automatic flow): without this, the banner
  /// would show on next launch until the periodic probe runs and rewrites
  /// the diagnostics.
  UpdateCheckDiagnostics _reconcileStaleAwaitingConsent(UpdateCheckDiagnostics restored) {
    if (restored.completionSource != UpdateCheckCompletionSource.automaticAwaitingUserConsent) {
      return restored;
    }
    final pendingVersion = restored.pendingVersion;
    if (pendingVersion == null || pendingVersion.isEmpty) return restored;
    final comparison = AppVersionComparator.compare(AppConstants.appVersion, pendingVersion);
    if (comparison < 0) return restored;
    developer.log(
      'Dropping stale automaticAwaitingUserConsent diagnostics: '
      'persisted pendingVersion=$pendingVersion <= current=${AppConstants.appVersion}',
      name: 'silent_update_coordinator',
      level: 800,
    );
    // copyWith preserves non-null fields via `?? this.x`, so we cannot
    // clear `pendingVersion` through it. Construct directly to drop both
    // the gate marker and the stale version pointer.
    return UpdateCheckDiagnostics(
      checkedAt: restored.checkedAt,
      configuredFeedUrl: restored.configuredFeedUrl,
      requestedFeedUrl: restored.requestedFeedUrl,
      checkId: restored.checkId,
      currentVersion: AppConstants.appVersion,
      probeRequestUrl: restored.probeRequestUrl,
      triggerStartedAt: restored.triggerStartedAt,
      triggerCompletedAt: restored.triggerCompletedAt,
      completedAt: restored.completedAt,
      completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
      probeSucceeded: restored.probeSucceeded,
      appcastProbeVersion: restored.appcastProbeVersion,
      appcastProbeOs: restored.appcastProbeOs,
      appcastProbeItemCount: restored.appcastProbeItemCount,
      updateAvailable: false,
      remoteVersion: restored.remoteVersion,
      remoteDisplayVersion: restored.remoteDisplayVersion,
      assetUrl: restored.assetUrl,
      assetSize: restored.assetSize,
      assetName: restored.assetName,
      sha256: restored.sha256,
      releaseNotes: restored.releaseNotes,
      releaseNotesUrl: restored.releaseNotesUrl,
      rolloutChannel: restored.rolloutChannel,
      rolloutPercentage: restored.rolloutPercentage,
      rolloutBucket: restored.rolloutBucket,
      rolloutEligible: restored.rolloutEligible,
      automaticFailureCount: restored.automaticFailureCount,
      automaticCooldownUntil: restored.automaticCooldownUntil,
      probeMatchesSparkle: restored.probeMatchesSparkle,
    );
  }

  @override
  Future<void> reconcilePendingAndSchedule() async {
    await _reconcilePendingSilentUpdate();
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;
    if (automaticSilentUpdatesEnabled) {
      scheduleAndStart();
    }
  }

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently({bool userInitiated = false}) async {
    if (_isSilentCheckInProgress) {
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.alreadyInProgress);
    }

    final feedUrl = _feedUrlResolver();
    if (!_capabilities.supportsAutoUpdate || feedUrl == null) {
      return Failure<SilentUpdateOutcome, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Silent auto-update is not available',
          context: <String, dynamic>{'operation': 'checkSilently'},
        ),
      );
    }

    _currentCheckId = _checkIdRecorder.newId();
    unawaited(_checkIdRecorder.record(_currentCheckId!, source: 'silent'));

    if (!automaticSilentUpdatesEnabled) {
      final now = DateTime.now();
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: _currentCheckId,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticDisabled,
        updateAvailable: false,
      );
      await _persistLastAutomaticDiagnostics();
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.silentDisabled);
    }

    // Quiet hours gate. Sits before installer/pending checks so the window
    // is honoured even when settings are mid-migration. The periodic timer
    // keeps firing; on the next tick outside the window the silent path
    // resumes normally.
    final environmentSnapshot = AppEnvironment.snapshot();
    final quietHoursStart = resolveAutoUpdateQuietHoursStartMinute(environment: environmentSnapshot);
    final quietHoursEnd = resolveAutoUpdateQuietHoursEndMinute(environment: environmentSnapshot);
    final quietNow = DateTime.now();
    final quietNowMinutes = quietNow.hour * 60 + quietNow.minute;
    if (isWithinQuietHoursWindow(
      nowMinutes: quietNowMinutes,
      startMinute: quietHoursStart,
      endMinute: quietHoursEnd,
    )) {
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: quietNow,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: _currentCheckId,
        currentVersion: AppConstants.appVersion,
        completedAt: quietNow,
        completionSource: UpdateCheckCompletionSource.automaticQuietHours,
        updateAvailable: false,
      );
      await _persistLastAutomaticDiagnostics();
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.skippedByQuietHours);
    }

    final installer = _silentUpdateInstaller;
    if (installer == null) {
      final now = DateTime.now();
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: _currentCheckId,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallFailure,
        errorMessage: 'Silent update installer is not configured',
      );
      await _persistLastAutomaticDiagnostics();
      return Failure<SilentUpdateOutcome, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Silent update installer is not configured',
          context: <String, dynamic>{'operation': 'checkSilently'},
        ),
      );
    }

    _isSilentCheckInProgress = true;
    _cancelRequested = false;
    try {
      final pending = _readPendingSilentUpdate();
      if (pending != null) {
        final now = DateTime.now();
        final launcherStatus = _readLauncherStatus(pending.launcherStatusPath);
        _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
          checkedAt: now,
          configuredFeedUrl: feedUrl,
          requestedFeedUrl: feedUrl,
          checkId: _currentCheckId,
          currentVersion: AppConstants.appVersion,
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
          pendingVersion: pending.version,
          installerPath: launcherStatus?.installerPath ?? pending.installerPath,
          installerLogPath: launcherStatus?.logPath ?? pending.logPath,
          installDirectory: launcherStatus?.installDirectory ?? pending.installDirectory,
          silentUpdateStrategy: launcherStatus?.strategy ?? pending.strategy,
          launcherPath: pending.launcherPath,
          launcherStatusPath: pending.launcherStatusPath,
          launcherState: launcherStatus?.state,
          nonAdminExitCode: launcherStatus?.nonAdminExitCode,
          nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
          elevatedExitCode: launcherStatus?.elevatedExitCode,
          elevatedDurationMs: launcherStatus?.elevatedDurationMs,
          elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
          waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
          appPid: launcherStatus?.appPid ?? pending.appPid,
          signatureStatus: launcherStatus?.signatureStatus,
          signatureRequired: launcherStatus?.signatureRequired,
          updateDirectorySecurityStatus: pending.updateDirectorySecurityStatus,
          actualSha256: launcherStatus?.actualSha256,
          hashValidationStatus: launcherStatus?.hashValidationStatus,
          installDirectoryWritable: launcherStatus?.installDirectoryWritable,
          elevatedCancelled: launcherStatus?.elevatedCancelled,
          errorMessage: 'Silent update already has a pending installer execution',
        );
        await _persistLastAutomaticDiagnostics();
        return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.pendingInProgress);
      }

      await _cleanupSilentUpdateArtifacts(installer);
      final cooldownResult = await _buildAutomaticCooldownResult(feedUrl);
      if (cooldownResult != null) {
        return cooldownResult;
      }

      final startedAt = DateTime.now();
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: startedAt,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: _currentCheckId,
        currentVersion: AppConstants.appVersion,
        probeRequestUrl: feedUrl,
      );
      await _persistLastAutomaticDiagnostics();

      // Capture bucket before the probe so the same value is used for both
      // diagnostics and eligibility; avoids generating two different random
      // numbers on first execution when the value is not yet persisted.
      final bucket = await _rolloutBucket();

      final probeStart = DateTime.now();
      final probeResult = await _appcastProbeService.probeLatest(feedUrl: feedUrl);
      _metricsCollector?.recordAutoUpdateProbeDuration(DateTime.now().difference(probeStart));
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        probeRequestUrl: probeResult.requestUrl,
        probeSucceeded: probeResult.errorMessage == null,
        appcastProbeVersion: probeResult.latestVersion,
        appcastProbeOs: probeResult.os,
        appcastProbeItemCount: probeResult.itemCount,
        remoteVersion: probeResult.latestVersion,
        remoteDisplayVersion: probeResult.latestVersion,
        assetUrl: probeResult.assetUrl,
        releaseNotes: probeResult.releaseNotes,
        releaseNotesUrl: probeResult.releaseNotesUrl,
        assetSize: probeResult.assetSize,
        assetName: probeResult.assetName,
        sha256: probeResult.sha256,
        rolloutChannel: probeResult.channel ?? defaultAutoUpdateChannel,
        rolloutPercentage: probeResult.rolloutPercentage ?? 100,
        rolloutBucket: bucket,
        probeErrorMessage: probeResult.errorMessage,
      );

      if (probeResult.errorMessage != null) {
        final now = DateTime.now();
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          errorMessage: probeResult.errorMessage,
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<SilentUpdateOutcome, Exception>(
          domain.NetworkFailure.withContext(
            message: 'Silent update appcast probe failed',
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': feedUrl,
              'probe_error': probeResult.errorMessage,
            },
          ),
        );
      }

      final validationError = _validateSilentProbeResult(probeResult);
      if (validationError != null) {
        final now = DateTime.now();
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          validationErrorCode: validationError.code,
          errorMessage: validationError.message,
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<SilentUpdateOutcome, Exception>(
          domain.ValidationFailure.withContext(
            message: validationError.message,
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': feedUrl,
              'validation_code': validationError.code,
            },
          ),
        );
      }

      final environment = AppEnvironment.snapshot();
      final feedSignatureRequired = resolveAutoUpdateRequireFeedSignature(environment: environment);
      final feedPublicKey = resolveAutoUpdateFeedPublicKey(environment: environment);
      final signatureStatus = await _signatureVerifier.verifyEnclosure(
        canonicalPayload: buildAppcastEnclosureSignable(
          version: probeResult.latestVersion!,
          os: probeResult.os ?? '',
          sha256: probeResult.sha256!,
          channel: probeResult.channel ?? defaultAutoUpdateChannel,
          rolloutPercentage: probeResult.rolloutPercentage ?? 100,
          assetUrl: probeResult.assetUrl!,
          assetSize: probeResult.assetSize!,
        ),
        base64Signature: probeResult.edSignature,
        base64PublicKey: feedPublicKey,
      );
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        feedSignatureStatus: signatureStatus.name,
        feedSignatureRequired: feedSignatureRequired,
      );
      if (feedSignatureRequired && signatureStatus != AppcastSignatureVerificationStatus.valid) {
        final now = DateTime.now();
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        final code = 'feed_signature_${signatureStatus.name}';
        final message =
            'Silent update appcast signature is required but '
            '${signatureStatus.name} (operator must publish a signed item or '
            'set AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=false to bypass)';
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          validationErrorCode: code,
          errorMessage: message,
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<SilentUpdateOutcome, Exception>(
          domain.ValidationFailure.withContext(
            message: message,
            context: <String, dynamic>{
              'operation': 'checkSilently',
              'feed_url': feedUrl,
              'validation_code': code,
              'signature_status': signatureStatus.name,
            },
          ),
        );
      }

      final remoteVersion = probeResult.latestVersion!;
      final rolloutEligible = _isProbeEligibleForConfiguredChannel(
        probeResult,
        rolloutBucket: bucket,
      );
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        rolloutEligible: rolloutEligible,
      );
      if (!rolloutEligible) {
        final now = DateTime.now();
        await _resetAutomaticFailureCooldownIfNeeded();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticRolloutSkipped,
          updateAvailable: false,
        );
        await _persistLastAutomaticDiagnostics();
        return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.rolloutSkipped);
      }

      final isNewer = AppVersionComparator.isRemoteVersionNewer(
        remoteVersion: remoteVersion,
        currentVersion: AppConstants.appVersion,
      );
      if (!isNewer) {
        final now = DateTime.now();
        await _resetAutomaticFailureCooldownIfNeeded();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
          updateAvailable: false,
        );
        await _persistLastAutomaticDiagnostics();
        return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.noNewVersion);
      }

      // UAC gate: when Windows would prompt the user for elevation
      // during install, the automatic flow must not download silently.
      // The probe already proved a newer version exists; surface that
      // state and stop here so the UI can prompt the operator. The
      // user-initiated path (`userInitiated: true`) bypasses the gate
      // because clicking "Install" is the consent we need.
      if (!userInitiated && _uacDetector.requiresUserConsentForElevation()) {
        final now = DateTime.now();
        await _resetAutomaticFailureCooldownIfNeeded();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: now,
          completionSource: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
          updateAvailable: true,
          pendingVersion: remoteVersion,
        );
        await _persistLastAutomaticDiagnostics();
        _metricsCollector?.recordAutoUpdateAwaitingUserConsent();
        _notifyDiagnosticsChanged();
        return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.requiresUserConsent);
      }

      final pendingUpdate = _PendingSilentUpdate(
        version: remoteVersion,
        installerPath: null,
        logPath: null,
        installDirectory: null,
        strategy: null,
        launcherPath: null,
        launcherStatusPath: null,
        appPid: null,
        updateDirectorySecurityStatus: null,
        startedAt: DateTime.now(),
      );
      await _persistPendingSilentUpdate(pendingUpdate);
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        updateAvailable: true,
        pendingVersion: remoteVersion,
        triggerStartedAt: DateTime.now(),
      );
      await _persistLastAutomaticDiagnostics();

      if (_cancelRequested) {
        return await _completeAutomaticCancellation(feedUrl);
      }

      final downloadStart = DateTime.now();
      final installResult = await installer.install(
        SilentUpdateInstallRequest(
          version: remoteVersion,
          assetUrl: probeResult.assetUrl!,
          assetSize: probeResult.assetSize!,
          assetName: probeResult.assetName!,
          sha256: probeResult.sha256!,
          requireValidSignature: resolveAutoUpdateRequireValidSignature(
            environment: AppEnvironment.snapshot(),
          ),
          cancelRequested: () => _cancelRequested,
          allowDownloadResume: resolveAutoUpdateDownloadResume(
            environment: AppEnvironment.snapshot(),
          ),
          // Stage the installer and helper on disk but do not launch the
          // helper yet: keeping the agent connected and operational is the
          // explicit contract. The helper is only fired when the operator
          // (or the natural app shutdown) calls
          // `applyPendingDownloadedUpdate`.
          deferHelperLaunch: true,
        ),
      );
      _metricsCollector?.recordAutoUpdateDownloadDuration(DateTime.now().difference(downloadStart));

      SilentUpdateInstallResult? installSuccess;
      Exception? installError;
      installResult.fold(
        (value) => installSuccess = value,
        (error) => installError = error,
      );

      final now = DateTime.now();
      if (installError != null) {
        if (_isCancellationFailure(installError!)) {
          return await _completeAutomaticCancellation(feedUrl);
        }
        await _clearPendingSilentUpdate();
        final completionSource = installError is domain.NetworkFailure
            ? UpdateCheckCompletionSource.automaticDownloadFailure
            : installError is domain.ValidationFailure
            ? UpdateCheckCompletionSource.automaticValidationFailure
            : UpdateCheckCompletionSource.automaticInstallFailure;
        final failureState = await _recordAutomaticFailureAndApplyCooldown();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          triggerCompletedAt: now,
          completedAt: now,
          completionSource: completionSource,
          automaticFailureCount: failureState.failureCount,
          automaticCooldownUntil: failureState.cooldownUntil,
          errorMessage: _extractFailureMessage(installError!),
        );
        await _persistLastAutomaticDiagnostics();
        return Failure<SilentUpdateOutcome, Exception>(installError!);
      }

      final success = installSuccess!;
      await _persistPendingSilentUpdate(
        _PendingSilentUpdate(
          version: remoteVersion,
          installerPath: success.installerPath,
          logPath: success.logPath,
          installDirectory: success.installDirectory,
          strategy: success.strategy.name,
          launcherPath: success.launcherPath,
          launcherStatusPath: success.launcherStatusPath,
          appPid: success.appPid,
          assetSize: probeResult.assetSize,
          sha256: probeResult.sha256,
          requireValidSignature: resolveAutoUpdateRequireValidSignature(
            environment: AppEnvironment.snapshot(),
          ),
          installDirectoryWritable: success.installDirectoryWritable,
          updateDirectorySecurityStatus: success.updateDirectorySecurityStatus,
          startedAt: DateTime.now(),
        ),
      );
      await _resetAutomaticFailureCooldownIfNeeded();
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        triggerCompletedAt: now,
        completedAt: now,
        // Surface the new "ready to apply" state so the UI can show the
        // in-app banner. The previous `automaticInstallStarted` value is
        // reserved for the user-initiated apply path below.
        completionSource: UpdateCheckCompletionSource.automaticInstallReady,
        installerPath: success.installerPath,
        installerLogPath: success.logPath,
        installDirectory: success.installDirectory,
        silentUpdateStrategy: success.strategy.name,
        launcherPath: success.launcherPath,
        launcherStatusPath: success.launcherStatusPath,
        appPid: success.appPid,
        updateDirectorySecurityStatus: success.updateDirectorySecurityStatus,
        installDirectoryWritable: success.installDirectoryWritable,
        helperSha256: success.helperSha256,
        helperSignatureStatus: success.helperSignatureStatus,
        signatureRequired: resolveAutoUpdateRequireValidSignature(
          environment: AppEnvironment.snapshot(),
        ),
      );
      await _persistLastAutomaticDiagnostics();
      await _settingsStore?.flushPendingPersistence();

      if (_cancelRequested) {
        return await _completeAutomaticCancellation(feedUrl);
      }

      // Check again after the download completed: the user may have disabled
      // automatic silent updates while the installer was being downloaded.
      if (!automaticSilentUpdatesEnabled) {
        await _clearPendingSilentUpdate();
        final disabledAt = DateTime.now();
        _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
          completedAt: disabledAt,
          completionSource: UpdateCheckCompletionSource.automaticDisabled,
          updateAvailable: false,
        );
        await _persistLastAutomaticDiagnostics();
        _notifyDiagnosticsChanged();
        return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.silentDisabled);
      }

      // New contract: the installer is staged on disk but the helper is
      // NOT launched and the app is NOT closed. Apply is now an explicit
      // step driven by the UI ("Install now" banner) or by the natural
      // app shutdown handler. The agent stays online and operational.
      _notifyDiagnosticsChanged();
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.installerReady);
    } on FormatException catch (error) {
      final now = DateTime.now();
      final failureState = await _recordAutomaticFailureAndApplyCooldown();
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
        automaticFailureCount: failureState.failureCount,
        automaticCooldownUntil: failureState.cooldownUntil,
        errorMessage: error.message,
      );
      await _persistLastAutomaticDiagnostics();
      return Failure<SilentUpdateOutcome, Exception>(
        domain.ValidationFailure.withContext(
          message: error.message,
          cause: error,
          context: <String, dynamic>{'operation': 'checkSilently'},
        ),
      );
    } finally {
      _isSilentCheckInProgress = false;
      _cancelRequested = false;
    }
  }

  bool _isCancellationFailure(Exception error) {
    if (error is! domain.Failure) return false;
    final value = error.context[SilentUpdateInstallRequest.cancellationContextKey];
    return value == true;
  }

  Future<Result<SilentUpdateOutcome>> _completeAutomaticCancellation(String feedUrl) async {
    await _clearPendingSilentUpdate();
    // Cancellation is a user-initiated state change, not a fault: do not
    // count it toward the automatic failure cooldown and clear any prior
    // cooldown so the user can resume immediately if they re-enable.
    await _resetAutomaticFailureCooldownIfNeeded();
    final now = DateTime.now();
    final existing = _lastAutomaticDiagnostics;
    _lastAutomaticDiagnostics =
        (existing ??
                UpdateCheckDiagnostics(
                  checkedAt: now,
                  configuredFeedUrl: feedUrl,
                  requestedFeedUrl: feedUrl,
                  checkId: _currentCheckId,
                  currentVersion: AppConstants.appVersion,
                ))
            .copyWith(
              completedAt: now,
              completionSource: UpdateCheckCompletionSource.automaticCancelled,
              updateAvailable: false,
              errorMessage: 'Silent update cancelled because automatic silent updates were disabled',
            );
    await _persistLastAutomaticDiagnostics();
    return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.cancelled);
  }

  @override
  void scheduleAndStart() {
    _scheduleAutomaticSilentChecks(runImmediately: true);
  }

  @override
  void stop() {
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;
  }

  @override
  void requestCancellation() {
    if (_isSilentCheckInProgress) {
      _cancelRequested = true;
    }
  }

  @override
  Future<void> resetFailureCooldownIfNeeded() async {
    await _resetAutomaticFailureCooldownIfNeeded();
  }

  @override
  bool get hasPendingDownloadedUpdate {
    final pending = _readPendingSilentUpdate();
    if (pending == null) return false;
    final installerPath = pending.installerPath;
    final launcherPath = pending.launcherPath;
    if (installerPath == null || launcherPath == null) {
      // Pending record without paths is a pre-download artifact, not a
      // ready-to-apply install.
      return false;
    }
    return File(installerPath).existsSync() && File(launcherPath).existsSync();
  }

  @override
  Future<Result<void>> applyPendingDownloadedUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    final pending = _readPendingSilentUpdate();
    if (pending == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'No prepared silent update is available to apply',
          context: <String, dynamic>{
            'operation': 'applyPendingDownloadedUpdate',
            'reason': 'no_pending_update',
          },
        ),
      );
    }
    final installer = _silentUpdateInstaller;
    if (installer == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Silent update installer is not configured',
          context: <String, dynamic>{
            'operation': 'applyPendingDownloadedUpdate',
            'reason': 'installer_not_configured',
          },
        ),
      );
    }
    final installerPath = pending.installerPath;
    final launcherPath = pending.launcherPath;
    final logPath = pending.logPath;
    final launcherStatusPath = pending.launcherStatusPath;
    final installDirectory = pending.installDirectory;
    final assetSize = pending.assetSize;
    final sha256 = pending.sha256;
    final installDirectoryWritable = pending.installDirectoryWritable;
    final requireValidSignature = pending.requireValidSignature;
    final appPid = pending.appPid;
    if (installerPath == null ||
        launcherPath == null ||
        logPath == null ||
        launcherStatusPath == null ||
        installDirectory == null ||
        assetSize == null ||
        sha256 == null ||
        installDirectoryWritable == null ||
        requireValidSignature == null ||
        appPid == null) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Pending silent update is missing helper launch metadata',
          context: <String, dynamic>{
            'operation': 'applyPendingDownloadedUpdate',
            'reason': 'incomplete_pending_record',
            'version': pending.version,
          },
        ),
      );
    }
    final launchResult = await installer.launchPreparedHelper(
      SilentUpdateLaunchRequest(
        version: pending.version,
        installerPath: installerPath,
        logPath: logPath,
        launcherPath: launcherPath,
        launcherStatusPath: launcherStatusPath,
        installDirectory: installDirectory,
        assetSize: assetSize,
        sha256: sha256,
        installDirectoryWritable: installDirectoryWritable,
        requireValidSignature: requireValidSignature,
        appPid: appPid,
      ),
    );
    Exception? launchError;
    launchResult.fold(
      (_) {},
      (error) => launchError = error,
    );
    if (launchError != null) {
      return Failure(launchError!);
    }

    final now = DateTime.now();
    _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
      completedAt: now,
      completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
    );
    await _persistLastAutomaticDiagnostics();
    _notifyDiagnosticsChanged();

    if (triggerAppClose) {
      final closeApplication = _closeApplicationForSilentUpdate;
      if (closeApplication != null) {
        unawaited(
          closeApplication(noticeTitle: noticeTitle, noticeBody: noticeBody),
        );
      }
    }
    return const Success(unit);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  void _notifyDiagnosticsChanged() {
    final callback = _onDiagnosticsChanged;
    if (callback == null) return;
    try {
      callback();
    } on Object catch (error, stackTrace) {
      developer.log(
        'onDiagnosticsChanged callback threw (ignored)',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _extractFailureMessage(Exception error) {
    if (error is domain.Failure) {
      return error.message;
    }
    return error.toString();
  }

  Future<void> _persistLastAutomaticDiagnostics() async {
    final settingsStore = _settingsStore;
    final diagnostics = _lastAutomaticDiagnostics;
    if (settingsStore == null || diagnostics == null) return;
    try {
      await settingsStore.setString(
        _lastAutomaticDiagnosticsKey,
        jsonEncode(diagnostics.toJson()),
      );
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist automatic silent update diagnostics',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  int _automaticFailureCount() => _settingsStore?.getInt(_automaticFailureCountKey) ?? 0;

  DateTime? _automaticCooldownUntil() {
    final timestamp = _settingsStore?.getInt(_automaticCooldownUntilKey);
    if (timestamp == null || timestamp <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  Future<void> _resetAutomaticFailureCooldownIfNeeded() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) return;
    final hasFailureCount = settingsStore.containsKey(_automaticFailureCountKey);
    final hasCooldown = settingsStore.containsKey(_automaticCooldownUntilKey);
    if (!hasFailureCount && !hasCooldown) return;
    try {
      await settingsStore.remove(_automaticFailureCountKey);
      await settingsStore.remove(_automaticCooldownUntilKey);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to reset automatic silent update cooldown state',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<({int failureCount, DateTime? cooldownUntil})> _recordAutomaticFailureAndApplyCooldown() async {
    final settingsStore = _settingsStore;
    if (settingsStore == null) return (failureCount: 0, cooldownUntil: null);
    final nextCount = _automaticFailureCount() + 1;
    DateTime? cooldownUntil;
    final values = <String, Object>{_automaticFailureCountKey: nextCount};
    if (nextCount >= _automaticFailureCooldownThreshold) {
      cooldownUntil = DateTime.now().add(_automaticFailureCooldown);
      values[_automaticCooldownUntilKey] = cooldownUntil.millisecondsSinceEpoch;
    }
    try {
      await settingsStore.setValues(values);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist automatic silent update cooldown state',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return (failureCount: nextCount, cooldownUntil: cooldownUntil);
  }

  Future<Result<SilentUpdateOutcome>?> _buildAutomaticCooldownResult(String feedUrl) async {
    final cooldownUntil = _automaticCooldownUntil();
    if (cooldownUntil == null) return null;
    final remaining = cooldownUntil.difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      await _resetAutomaticFailureCooldownIfNeeded();
      return null;
    }
    final minutesRemaining = remaining.inMinutes;
    final humanRemaining = minutesRemaining >= 1 ? '$minutesRemaining min' : '${remaining.inSeconds}s';
    final now = DateTime.now();
    _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      checkId: _currentCheckId,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: UpdateCheckCompletionSource.automaticCooldown,
      updateAvailable: false,
      automaticFailureCount: _automaticFailureCount(),
      automaticCooldownUntil: cooldownUntil,
      errorMessage: 'Automatic silent updates are paused after repeated failures. Try again in about $humanRemaining.',
    );
    await _persistLastAutomaticDiagnostics();
    return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.cooldownActive);
  }

  Future<void> _cleanupSilentUpdateArtifacts(ISilentUpdateInstaller installer) async {
    final cleanupResult = await installer.cleanupObsoleteArtifacts();
    cleanupResult.fold(
      (_) {},
      (error) {
        developer.log(
          'Silent update artifact cleanup failed',
          name: 'silent_update_coordinator',
          level: 900,
          error: error,
        );
      },
    );
  }

  Future<int> _rolloutBucket() async {
    final existing = _settingsStore?.getInt(_automaticRolloutBucketKey);
    if (existing != null && existing >= 0 && existing < 100) return existing;
    final generated = Random.secure().nextInt(100);
    final settingsStore = _settingsStore;
    if (settingsStore != null) {
      try {
        await settingsStore.setInt(_automaticRolloutBucketKey, generated);
      } on Exception catch (error, stackTrace) {
        developer.log(
          'Failed to persist rollout bucket; using in-memory value for this check',
          name: 'silent_update_coordinator',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return generated;
  }

  bool _isProbeEligibleForConfiguredChannel(
    AppcastProbeResult result, {
    required int rolloutBucket,
  }) {
    final configuredChannel = resolveAutoUpdateChannel(environment: AppEnvironment.snapshot());
    final remoteChannel = (result.channel == null || result.channel!.isEmpty)
        ? defaultAutoUpdateChannel
        : result.channel!.toLowerCase();
    if (remoteChannel != configuredChannel) return false;
    final rolloutPercentage = result.rolloutPercentage ?? 100;
    return rolloutPercentage >= 100 || rolloutBucket < rolloutPercentage;
  }

  void _scheduleAutomaticSilentChecks({required bool runImmediately}) {
    _automaticCheckTimer?.cancel();
    _automaticCheckTimer = null;
    if (runImmediately) {
      final jitter = _bootJitterProvider?.call();
      if (jitter == null || jitter <= Duration.zero) {
        unawaited(checkSilently());
      } else {
        Timer(jitter, () => unawaited(checkSilently()));
      }
    }
    final intervalSeconds = resolveAutoUpdateCheckIntervalSeconds(
      environment: AppEnvironment.snapshot(),
    );
    if (intervalSeconds > 0) {
      _automaticCheckTimer = Timer.periodic(
        Duration(seconds: intervalSeconds),
        (_) => unawaited(checkSilently()),
      );
    }
  }

  _SilentProbeValidationError? _validateSilentProbeResult(AppcastProbeResult result) {
    final version = result.latestVersion?.trim();
    if (version == null || version.isEmpty) {
      return const _SilentProbeValidationError(
        code: 'missing_latest_version',
        message: 'Silent update appcast is missing the latest version',
      );
    }
    final assetUrl = result.assetUrl?.trim();
    if (assetUrl == null || assetUrl.isEmpty) {
      return const _SilentProbeValidationError(
        code: 'missing_asset_url',
        message: 'Silent update appcast is missing the installer URL',
      );
    }
    if (!isAutoUpdateInstallerUrl(assetUrl)) {
      return const _SilentProbeValidationError(
        code: 'invalid_asset_url',
        message: 'Silent update appcast has an invalid installer URL',
      );
    }
    final os = result.os?.trim().toLowerCase();
    if (os != null && os.isNotEmpty && os != 'windows') {
      return const _SilentProbeValidationError(
        code: 'unsupported_os',
        message: 'Silent update appcast targets an unsupported operating system',
      );
    }
    final assetSize = result.assetSize;
    if (assetSize == null || assetSize <= 0) {
      return const _SilentProbeValidationError(
        code: 'invalid_asset_size',
        message: 'Silent update appcast is missing a valid installer size',
      );
    }
    final assetName = result.assetName?.trim();
    if (assetName == null || assetName.isEmpty || !assetName.toLowerCase().endsWith('.exe')) {
      return const _SilentProbeValidationError(
        code: 'invalid_asset_name',
        message: 'Silent update appcast is missing a valid installer name',
      );
    }
    final sha256 = result.sha256?.trim().toLowerCase();
    if (sha256 == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      return const _SilentProbeValidationError(
        code: 'invalid_sha256',
        message: 'Silent update appcast is missing a valid plug:sha256 digest',
      );
    }
    final rolloutPercentage = result.rolloutPercentage;
    if (rolloutPercentage != null && (rolloutPercentage < 0 || rolloutPercentage > 100)) {
      return const _SilentProbeValidationError(
        code: 'invalid_rollout_percentage',
        message: 'Silent update appcast has an invalid plug:rolloutPercentage value',
      );
    }
    return null;
  }

  Future<void> _reconcilePendingSilentUpdate() async {
    final pending = _readPendingSilentUpdate();
    if (pending == null) return;
    _currentCheckId = _checkIdRecorder.newId();
    unawaited(_checkIdRecorder.record(_currentCheckId!, source: 'reconcile'));
    final feedUrl = _feedUrlResolver() ?? officialAutoUpdateFeedUrl;
    final now = DateTime.now();
    final launcherStatus = _readLauncherStatus(pending.launcherStatusPath);
    bool completed;
    try {
      completed = AppVersionComparator.compare(AppConstants.appVersion, pending.version) >= 0;
    } on FormatException {
      completed = false;
    }
    if (!completed && launcherStatus == null && _isPendingStale(pending)) {
      developer.log(
        'Clearing stale pending silent update (paths no longer exist): version=${pending.version}',
        name: 'silent_update_coordinator',
        level: 800,
      );
      await _clearPendingSilentUpdate();
      return;
    }
    if (!completed && _shouldKeepPendingSilentUpdate(pending, launcherStatus, now)) {
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: now,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: _currentCheckId,
        currentVersion: AppConstants.appVersion,
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
        updateAvailable: true,
        pendingVersion: pending.version,
        installerPath: launcherStatus?.installerPath ?? pending.installerPath,
        installerLogPath: launcherStatus?.logPath ?? pending.logPath,
        installDirectory: launcherStatus?.installDirectory ?? pending.installDirectory,
        silentUpdateStrategy: launcherStatus?.strategy ?? pending.strategy,
        launcherPath: pending.launcherPath,
        launcherStatusPath: pending.launcherStatusPath,
        launcherState: launcherStatus?.state,
        nonAdminExitCode: launcherStatus?.nonAdminExitCode,
        nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
        elevatedExitCode: launcherStatus?.elevatedExitCode,
        elevatedDurationMs: launcherStatus?.elevatedDurationMs,
        elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
        waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
        appPid: launcherStatus?.appPid ?? pending.appPid,
        signatureStatus: launcherStatus?.signatureStatus,
        signatureRequired: launcherStatus?.signatureRequired,
        updateDirectorySecurityStatus: pending.updateDirectorySecurityStatus,
        actualSha256: launcherStatus?.actualSha256,
        hashValidationStatus: launcherStatus?.hashValidationStatus,
        installDirectoryWritable: launcherStatus?.installDirectoryWritable,
        elevatedCancelled: launcherStatus?.elevatedCancelled,
        errorMessage: 'Silent update installer is still running',
      );
      await _persistLastAutomaticDiagnostics();
      return;
    }
    final failureState = completed ? null : await _recordAutomaticFailureAndApplyCooldown();
    if (completed) {
      await _resetAutomaticFailureCooldownIfNeeded();
    }
    _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      checkId: _currentCheckId,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: completed
          ? UpdateCheckCompletionSource.automaticPendingCompleted
          : UpdateCheckCompletionSource.automaticPendingFailed,
      updateAvailable: !completed,
      pendingVersion: pending.version,
      installerPath: launcherStatus?.installerPath ?? pending.installerPath,
      installerLogPath: launcherStatus?.logPath ?? pending.logPath,
      installDirectory: launcherStatus?.installDirectory ?? pending.installDirectory,
      silentUpdateStrategy: launcherStatus?.strategy ?? pending.strategy,
      launcherPath: pending.launcherPath,
      launcherStatusPath: pending.launcherStatusPath,
      launcherState: launcherStatus?.state,
      nonAdminExitCode: launcherStatus?.nonAdminExitCode,
      nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
      elevatedExitCode: launcherStatus?.elevatedExitCode,
      elevatedDurationMs: launcherStatus?.elevatedDurationMs,
      elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
      waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
      appPid: launcherStatus?.appPid ?? pending.appPid,
      signatureStatus: launcherStatus?.signatureStatus,
      signatureRequired: launcherStatus?.signatureRequired,
      updateDirectorySecurityStatus: pending.updateDirectorySecurityStatus,
      actualSha256: launcherStatus?.actualSha256,
      hashValidationStatus: launcherStatus?.hashValidationStatus,
      installDirectoryWritable: launcherStatus?.installDirectoryWritable,
      elevatedCancelled: launcherStatus?.elevatedCancelled,
      automaticFailureCount: failureState?.failureCount,
      automaticCooldownUntil: failureState?.cooldownUntil,
      errorMessage: completed ? null : launcherStatus?.failureMessage ?? 'Pending silent update did not complete',
    );
    await _persistLastAutomaticDiagnostics();
    await _clearPendingSilentUpdate();
  }

  bool _isPendingStale(_PendingSilentUpdate pending) {
    final installerPath = pending.installerPath;
    final launcherPath = pending.launcherPath;
    final statusPath = pending.launcherStatusPath;
    // A pending with no paths was written before the download started (the
    // coordinator persists the pending record before calling installer.install).
    // If the process crashed or the download failed silently between that
    // persist and the post-download update, the record stays with null paths
    // forever and blocks future update checks. Treat it as stale so the next
    // checkSilently() can start a fresh download cycle.
    if (installerPath == null && launcherPath == null) return true;
    final installerMissing = installerPath == null || !File(installerPath).existsSync();
    final launcherMissing = launcherPath == null || !File(launcherPath).existsSync();
    final statusMissing = statusPath == null || !File(statusPath).existsSync();
    return installerMissing && launcherMissing && statusMissing;
  }

  bool _shouldKeepPendingSilentUpdate(
    _PendingSilentUpdate pending,
    _SilentUpdateLauncherStatus? launcherStatus,
    DateTime now,
  ) {
    final startedAt = launcherStatus?.lastUpdatedAt ?? pending.startedAt;
    if (startedAt == null || now.difference(startedAt) > _helperWaitDuration) return false;
    final state = launcherStatus?.state;
    return state == null ||
        state == 'started' ||
        state == 'waitingForAppExit' ||
        state == 'nonAdminStarted' ||
        state == 'elevatedStarted';
  }

  _PendingSilentUpdate? _readPendingSilentUpdate() {
    final raw = _settingsStore?.getString(_pendingSilentUpdateKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _PendingSilentUpdate.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse pending silent update state',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  Future<void> _persistPendingSilentUpdate(_PendingSilentUpdate pending) async {
    await _settingsStore?.setString(
      _pendingSilentUpdateKey,
      jsonEncode(pending.toJson()),
    );
  }

  Future<void> _clearPendingSilentUpdate() async {
    await _settingsStore?.remove(_pendingSilentUpdateKey);
  }

  _SilentUpdateLauncherStatus? _readLauncherStatus(String? statusPath) {
    if (statusPath == null || statusPath.isEmpty) return null;
    try {
      final statusFile = File(statusPath);
      if (!statusFile.existsSync()) return null;
      final decoded = jsonDecode(statusFile.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        return _SilentUpdateLauncherStatus.fromJson(decoded);
      }
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to read silent update launcher status',
        name: 'silent_update_coordinator',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Private data models (silent path only)
// ---------------------------------------------------------------------------

class _SilentProbeValidationError {
  const _SilentProbeValidationError({required this.code, required this.message});
  final String code;
  final String message;
}

class _PendingSilentUpdate {
  const _PendingSilentUpdate({
    required this.version,
    required this.installerPath,
    required this.logPath,
    required this.installDirectory,
    required this.strategy,
    required this.launcherPath,
    required this.launcherStatusPath,
    required this.appPid,
    required this.updateDirectorySecurityStatus,
    required this.startedAt,
    this.assetSize,
    this.sha256,
    this.installDirectoryWritable,
    this.requireValidSignature,
  });

  final String version;
  final String? installerPath;
  final String? logPath;
  final String? installDirectory;
  final String? strategy;
  final String? launcherPath;
  final String? launcherStatusPath;
  final int? appPid;
  final String? updateDirectorySecurityStatus;
  final DateTime? startedAt;
  // Extra fields persisted so the apply step can rebuild a launch request
  // even after a process restart (the in-memory probe result is gone by
  // then). Nullable for backward compatibility with records written by
  // older versions of the agent that still ran the auto-close flow.
  final int? assetSize;
  final String? sha256;
  final bool? installDirectoryWritable;
  final bool? requireValidSignature;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'installerPath': installerPath,
      'logPath': logPath,
      'installDirectory': installDirectory,
      'strategy': strategy,
      'launcherPath': launcherPath,
      'launcherStatusPath': launcherStatusPath,
      'appPid': appPid,
      'updateDirectorySecurityStatus': updateDirectorySecurityStatus,
      'startedAt': (startedAt ?? DateTime.now()).toIso8601String(),
      'assetSize': assetSize,
      'sha256': sha256,
      'installDirectoryWritable': installDirectoryWritable,
      'requireValidSignature': requireValidSignature,
    };
  }

  static _PendingSilentUpdate? fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    if (version is! String || version.isEmpty) return null;
    return _PendingSilentUpdate(
      version: version,
      installerPath: json['installerPath'] as String?,
      logPath: json['logPath'] as String?,
      installDirectory: json['installDirectory'] as String?,
      strategy: json['strategy'] as String?,
      launcherPath: json['launcherPath'] as String?,
      launcherStatusPath: json['launcherStatusPath'] as String?,
      appPid: _readInt(json['appPid']),
      updateDirectorySecurityStatus: json['updateDirectorySecurityStatus'] as String?,
      startedAt: _readDateTime(json['startedAt']),
      assetSize: _readInt(json['assetSize']),
      sha256: json['sha256'] as String?,
      installDirectoryWritable: json['installDirectoryWritable'] as bool?,
      requireValidSignature: json['requireValidSignature'] as bool?,
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}

class _SilentUpdateLauncherStatus {
  const _SilentUpdateLauncherStatus({
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
    if (errorMessage != null && errorMessage!.isNotEmpty) return errorMessage;
    if (state != null && state!.isNotEmpty) return 'Launcher status: $state';
    return null;
  }

  static _SilentUpdateLauncherStatus fromJson(Map<String, dynamic> json) {
    return _SilentUpdateLauncherStatus(
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

  static int? _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
