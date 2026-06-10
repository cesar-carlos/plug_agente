import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' show VoidCallback;

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/degraded_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_defaults.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/pending_silent_update_reconciler.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/silent_update_diagnostics_store.dart';
import 'package:plug_agente/application/services/silent_update_download_apply_service.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/application/services/silent_update_probe_pipeline.dart';
import 'package:plug_agente/application/services/silent_update_scheduler.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

export 'package:plug_agente/application/services/silent_update_download_apply_service.dart'
    show CloseApplicationForSilentUpdate;

abstract interface class ISilentUpdateCoordinator {
  bool get isSilentCheckInProgress;
  bool get automaticSilentUpdatesEnabled;
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics;

  /// True when a silent download finished and the installer is staged on
  /// disk awaiting an explicit apply. The agent stays fully connected and
  /// operational while this is `true`.
  Future<bool> get hasPendingDownloadedUpdate;

  void hydratePersistedDiagnostics();

  /// Clears in-memory and persisted automatic silent-update diagnostics.
  Future<void> clearPersistedAutomaticDiagnostics();

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

  /// Starts or restarts the periodic timer. When [runImmediately] is
  /// `true` (default), also runs a check right away (after the optional
  /// boot jitter). Callers that just finished an apply and triggered a
  /// close pass `false` so a new probe does not race the shutdown.
  void scheduleAndStart({bool runImmediately = true});

  /// Cancels the periodic timer without touching persisted state.
  void stop();

  /// Asks the coordinator to abort the in-flight silent check at the next
  /// safe checkpoint (between download chunks, before launching the helper).
  /// No-op when no check is running. The coordinator clears its cancel flag
  /// at the beginning of the next [checkSilently] invocation.
  void requestCancellation();
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
    IAppcastProbeService? appcastProbeService,
    ISilentUpdateInstaller? silentUpdateInstaller,
    IAppSettingsStore? settingsStore,
    IUpdatePreferencesRepository? updatePreferencesRepository,
    CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
    VoidCallback? onDiagnosticsChanged,
    int automaticFailureCooldownThreshold = AutoUpdateDefaults.automaticFailureCooldownThreshold,
    Duration automaticFailureCooldown = AutoUpdateDefaults.automaticFailureCooldown,
    Duration helperWaitDuration = AutoUpdateDefaults.helperWaitDuration,
    Duration Function()? bootJitterProvider,
    IAppcastSignatureVerifier? signatureVerifier,
    UpdateCheckIdRecorder? checkIdRecorder,
    IAutoUpdateMetricsCollector? metricsCollector,
    IAutoUpdateDiagnosticsGateway? diagnosticsGateway,
    IUacDetector? uacDetector,
    IPendingSilentUpdateStore? pendingStore,
    ISilentUpdateLauncherStatusReader? launcherStatusReader,
    SilentUpdateDiagnosticsStore? diagnosticsStore,
    SilentUpdateScheduler? scheduler,
    SilentUpdateDownloadApplyService? downloadApplyService,
    PendingSilentUpdateReconciler? pendingReconciler,
    DateTime Function()? clock,
  }) : _appcastProbeService = appcastProbeService ?? AppcastProbeService(),
       _silentUpdateInstaller = silentUpdateInstaller,
       _preferences =
           updatePreferencesRepository ??
           (settingsStore != null ? UpdatePreferencesRepository(settingsStore: settingsStore) : null),
       _closeApplicationForSilentUpdate = closeApplicationForSilentUpdate,
       _onDiagnosticsChanged = onDiagnosticsChanged,
       _helperWaitDuration = helperWaitDuration,
       _signatureVerifier = signatureVerifier ?? Ed25519AppcastSignatureVerifier(),
       _checkIdRecorder = checkIdRecorder ?? UpdateCheckIdRecorder(settingsStore: settingsStore),
       _metricsCollector = metricsCollector,
       _diagnosticsGateway = diagnosticsGateway,
       _uacDetector = uacDetector ?? const NoopUacDetector(),
       _launcherStatusReader = launcherStatusReader ?? const NoopSilentUpdateLauncherStatusReader(),
       _clock = clock ?? DateTime.now {
    final wiredPreferences = _preferences ?? DegradedUpdatePreferencesRepository();
    _automaticFailureBreaker = PersistentCircuitBreaker(
      persistence: wiredPreferences.automaticFailureCircuitPersistence(),
      threshold: automaticFailureCooldownThreshold,
      cooldown: automaticFailureCooldown,
      logName: 'silent_update_coordinator',
      clock: clock,
    );
    _pendingStore =
        pendingStore ??
        (_preferences != null
            ? SettingsBackedPendingSilentUpdateStore(preferences: _preferences)
            : InMemoryPendingSilentUpdateStore());
    _diagnosticsStore =
        diagnosticsStore ??
        SilentUpdateDiagnosticsStore(
          preferences: wiredPreferences,
        );
    _scheduler =
        scheduler ??
        SilentUpdateScheduler(
          automaticFailureBreaker: _automaticFailureBreaker,
          bootJitterProvider: bootJitterProvider,
          clock: clock,
        );
    _probePipeline = SilentUpdateProbePipeline(
      appcastProbeService: _appcastProbeService,
      signatureVerifier: _signatureVerifier,
      uacDetector: _uacDetector,
      pendingStore: _pendingStore,
      automaticFailureBreaker: _automaticFailureBreaker,
      metricsCollector: _metricsCollector,
      clock: _clock,
    );
    _downloadApplyService =
        downloadApplyService ??
        SilentUpdateDownloadApplyService(
          installer: _silentUpdateInstaller,
          pendingStore: _pendingStore,
          automaticFailureBreaker: _automaticFailureBreaker,
          launcherStatusReader: _launcherStatusReader,
          preferences: _preferences,
          metricsCollector: _metricsCollector,
          closeApplicationForSilentUpdate: _closeApplicationForSilentUpdate,
          clock: _clock,
        );
    _pendingReconciler =
        pendingReconciler ??
        PendingSilentUpdateReconciler(
          pendingStore: _pendingStore,
          launcherStatusReader: _launcherStatusReader,
          automaticFailureBreaker: _automaticFailureBreaker,
          feedUrlResolver: _feedUrlResolver,
          checkIdRecorder: _checkIdRecorder,
          helperWaitDuration: _helperWaitDuration,
          clock: _clock,
        );
    _warnIfUacDetectorIsNoopOnSupportedRuntime();
    hydratePersistedDiagnostics();
  }

  /// Logs a loud warning when the runtime *does* support auto-update
  /// (so silent installs can actually trigger UAC prompts), yet the
  /// injected detector is the no-op fallback. Catches DI mistakes early
  /// instead of letting the UAC gate silently approve every install.
  void _warnIfUacDetectorIsNoopOnSupportedRuntime() {
    if (!_capabilities.supportsAutoUpdate) return;
    if (_uacDetector is! NoopUacDetector) return;
    developer.log(
      'SilentUpdateCoordinator is using NoopUacDetector on a runtime '
      'that supports auto-update (supportsAutoUpdate=true). The UAC '
      'gate will never engage; verify the DI registrar wires a real '
      'detector (e.g. WindowsUacDetector) on Windows.',
      name: 'silent_update_coordinator',
      level: 900,
    );
  }

  final RuntimeCapabilities _capabilities;

  /// Returns the current resolved feed URL, or `null` when not configured.
  final String? Function() _feedUrlResolver;
  final IAppcastProbeService _appcastProbeService;
  final ISilentUpdateInstaller? _silentUpdateInstaller;
  final IUpdatePreferencesRepository? _preferences;
  final CloseApplicationForSilentUpdate? _closeApplicationForSilentUpdate;
  final VoidCallback? _onDiagnosticsChanged;
  final Duration _helperWaitDuration;
  late final SilentUpdateDiagnosticsStore _diagnosticsStore;
  late final SilentUpdateScheduler _scheduler;
  late final SilentUpdateProbePipeline _probePipeline;
  late final SilentUpdateDownloadApplyService _downloadApplyService;
  late final PendingSilentUpdateReconciler _pendingReconciler;

  /// Ed25519 verifier for `plug:edSignature`. Default is the pure-Dart
  /// implementation; tests can inject a deterministic fake.
  final IAppcastSignatureVerifier _signatureVerifier;

  /// Generates UUIDv7 correlation IDs for each silent cycle and keeps a
  /// ring buffer of recent IDs for offline log correlation.
  final UpdateCheckIdRecorder _checkIdRecorder;

  /// Optional metrics sink for probe/download duration histograms. `null`
  /// disables sampling (tests / minimal DI).
  final IAutoUpdateMetricsCollector? _metricsCollector;

  /// Optional best-effort push of a non-sensitive subset of diagnostics
  /// to the hub at the end of each silent cycle. Never propagates errors:
  /// a flaky transport must not break the update flow.
  final IAutoUpdateDiagnosticsGateway? _diagnosticsGateway;

  /// Detects whether applying an update would trigger a UAC prompt.
  /// Defaults to a no-op when not configured (test/non-Windows). The
  /// automatic flow honours the detector; manual / user-initiated checks
  /// bypass it because the operator has already consented to the
  /// upcoming UAC prompt by clicking "Install".
  final IUacDetector _uacDetector;

  /// Persistence boundary for the in-flight/staged install record.
  /// Hides `dart:io` from the application layer.
  late final IPendingSilentUpdateStore _pendingStore;

  /// Reads the on-disk helper status file. Hides `dart:io`.
  final ISilentUpdateLauncherStatusReader _launcherStatusReader;

  /// Injected clock so tests can control "now" without sleeping and so
  /// late-callback detection survives NTP step adjustments. Returns
  /// wall-clock by default.
  final DateTime Function() _clock;

  /// Reusable circuit breaker that ladders failures into a cooldown
  /// window so the silent flow stops hammering a degraded feed.
  late final PersistentCircuitBreaker _automaticFailureBreaker;

  bool _isSilentCheckInProgress = false;
  bool _cancelRequested = false;

  /// Set once a prepared helper has been launched in this session. Guards
  /// against a double launch when both the UI "Install now" action
  /// (`triggerAppClose: true`) and the shutdown path
  /// (`triggerAppClose: false`) fire for the same pending record: the native
  /// helper holds a global mutex, so a second launch would only overwrite a
  UpdateCheckDiagnostics? get _lastAutomaticDiagnostics => _diagnosticsStore.lastAutomaticDiagnostics;

  set _lastAutomaticDiagnostics(UpdateCheckDiagnostics? value) {
    _diagnosticsStore.lastAutomaticDiagnostics = value;
  }

  /// Set at the start of every silent cycle (`checkSilently` /
  /// `_reconcilePendingSilentUpdate`) and propagated to all
  /// `UpdateCheckDiagnostics` constructed during that cycle.
  String? _currentCheckId;

  // Shared defaults live in `AutoUpdateDefaults` so the orchestrator
  // and the coordinator do not need cross-class "public alias"
  // constants to stay in sync.

  // ---------------------------------------------------------------------------
  // Public interface
  // ---------------------------------------------------------------------------

  @override
  bool get isSilentCheckInProgress => _isSilentCheckInProgress;

  @override
  bool get automaticSilentUpdatesEnabled => _preferences?.automaticSilentUpdatesEnabled ?? true;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => _diagnosticsStore.lastAutomaticDiagnostics;

  @override
  void hydratePersistedDiagnostics() => _diagnosticsStore.hydrate();

  @override
  Future<void> clearPersistedAutomaticDiagnostics() => _diagnosticsStore.clearPersisted();

  @override
  Future<void> reconcilePendingAndSchedule() async {
    await _reconcilePendingSilentUpdate();
    _scheduler.stop();
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
      final now = _clock();
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
      _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.silentDisabled);
    }

    // Quiet hours gate. Sits before installer/pending checks so the window
    // is honoured even when settings are mid-migration. The periodic timer
    // keeps firing; on the next tick outside the window the silent path
    // resumes normally.
    if (_scheduler.isWithinQuietHours()) {
      final quietNow = _clock();
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
      _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.skippedByQuietHours);
    }

    final installer = _silentUpdateInstaller;
    if (installer == null) {
      final now = _clock();
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
      _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
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
      final pending = await _pendingStore.read();
      if (pending != null && pending is PendingSilentUpdateDownloaded) {
        final now = _clock();
        final launcherStatus = await _launcherStatusReader.read(pending.launcherStatusPath);
        _lastAutomaticDiagnostics = PendingSilentUpdateReconciler.diagnosticsForPending(
          pending: pending,
          launcherStatus: launcherStatus,
          feedUrl: feedUrl,
          now: now,
          checkId: _currentCheckId,
          completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
          errorMessage: 'Silent update already has a pending installer execution',
        );
        await _persistLastAutomaticDiagnostics();
        _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
        return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.pendingInProgress);
      }

      await _downloadApplyService.cleanupArtifacts(installer);
      final cooldownResult = await _scheduler.buildCooldownResult(
        feedUrl: feedUrl,
        checkId: _currentCheckId,
        onDiagnostics: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
        persistDiagnostics: _persistLastAutomaticDiagnostics,
      );
      if (cooldownResult != null) {
        _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
        return cooldownResult;
      }

      final startedAt = _clock();
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
      final probeDiagnostics = _lastAutomaticDiagnostics!;
      final probePipelineResult = await _probePipeline.run(
        SilentUpdateProbePipelineRequest(
          feedUrl: feedUrl,
          checkId: _currentCheckId,
          userInitiated: userInitiated,
          cancelRequested: () => _cancelRequested,
          rolloutBucket: bucket,
          diagnostics: probeDiagnostics,
          onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
          persistDiagnostics: _persistLastAutomaticDiagnostics,
        ),
      );

      late final AppcastProbeResult probeResult;
      late final String remoteVersion;
      switch (probePipelineResult) {
        case SilentUpdateProbeTerminal(:final outcome, :final notifyDiagnostics):
          if (notifyDiagnostics) {
            _notifyDiagnosticsChanged();
          }
          _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
          return outcome;
        case SilentUpdateProbeCancelled():
          final outcome = await _completeAutomaticCancellation(feedUrl);
          _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
          return outcome;
        case SilentUpdateProbeProceedToDownload(
          probeResult: final probed,
          remoteVersion: final version,
        ):
          probeResult = probed;
          remoteVersion = version;
      }

      final stageResult = await _downloadApplyService.downloadAndStage(
        SilentUpdateDownloadStageRequest(
          probeResult: probeResult,
          remoteVersion: remoteVersion,
          cancelRequested: () => _cancelRequested,
          automaticSilentUpdatesEnabled: () => automaticSilentUpdatesEnabled,
          getDiagnostics: () => _lastAutomaticDiagnostics,
          onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
          persistDiagnostics: _persistLastAutomaticDiagnostics,
          notifyDiagnosticsChanged: _notifyDiagnosticsChanged,
        ),
      );
      switch (stageResult) {
        case SilentUpdateDownloadStageCancelled():
          final outcome = await _completeAutomaticCancellation(feedUrl);
          _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
          return outcome;
        case SilentUpdateDownloadStageFailure(:final error):
          _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
          return Failure<SilentUpdateOutcome, Exception>(error);
        case SilentUpdateDownloadStageDisabled():
          _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
          return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.silentDisabled);
        case SilentUpdateDownloadStageReady():
          _notifyDiagnosticsChanged();
          _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
          return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.installerReady);
      }
    } on FormatException catch (error) {
      final now = _clock();
      final failureState = await _automaticFailureBreaker.recordFailure();
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
        automaticFailureCount: failureState.failureCount,
        automaticCooldownUntil: failureState.cooldownUntil,
        errorMessage: error.message,
      );
      await _persistLastAutomaticDiagnostics();
      _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.silent);
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

  Future<Result<SilentUpdateOutcome>> _completeAutomaticCancellation(String feedUrl) async {
    await _pendingStore.clear();
    // Cancellation is a user-initiated state change, not a fault: do not
    // count it toward the automatic failure cooldown and clear any prior
    // cooldown so the user can resume immediately if they re-enable.
    await _automaticFailureBreaker.reset();
    final now = _clock();
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
  void scheduleAndStart({bool runImmediately = true}) {
    _scheduler.scheduleAndStart(
      runImmediately: runImmediately,
      onCheck: checkSilently,
    );
  }

  @override
  void stop() => _scheduler.stop();

  @override
  void requestCancellation() {
    if (_isSilentCheckInProgress) {
      _cancelRequested = true;
    }
  }

  @override
  Future<bool> get hasPendingDownloadedUpdate => _downloadApplyService.hasPendingDownloadedUpdate();

  @override
  Future<Result<void>> applyPendingDownloadedUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) {
    return _downloadApplyService.applyPendingDownloadedUpdate(
      noticeTitle: noticeTitle,
      noticeBody: noticeBody,
      triggerAppClose: triggerAppClose,
      getDiagnostics: () => _lastAutomaticDiagnostics,
      onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
      persistDiagnostics: _persistLastAutomaticDiagnostics,
      notifyDiagnosticsChanged: _notifyDiagnosticsChanged,
    );
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

  /// Best-effort push of the latest automatic diagnostics to the hub. The
  /// telemetry contract demands the gateway throttle, omit sensitive
  /// fields and swallow errors, so this method never awaits the future
  /// and never propagates exceptions.
  void _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource source) {
    final gateway = _diagnosticsGateway;
    final diagnostics = _lastAutomaticDiagnostics;
    if (gateway == null || diagnostics == null) return;
    unawaited(
      Future<void>(() async {
        try {
          await gateway.push(diagnostics: diagnostics, source: source);
        } on Object catch (error, stackTrace) {
          developer.log(
            'Auto-update diagnostics push threw (ignored)',
            name: 'silent_update_coordinator',
            level: 800,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
  }

  Future<void> _persistLastAutomaticDiagnostics() => _diagnosticsStore.persist();

  Future<int> _rolloutBucket() async {
    final existing = _preferences?.readRolloutBucket();
    if (existing != null && existing >= 0 && existing < 100) return existing;
    final generated = Random.secure().nextInt(100);
    final preferences = _preferences;
    if (preferences != null) {
      try {
        await preferences.writeRolloutBucket(generated);
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

  Future<void> _reconcilePendingSilentUpdate() async {
    await _pendingReconciler.reconcile(
      PendingSilentUpdateReconcileRequest(
        onCheckIdAssigned: (checkId) => _currentCheckId = checkId,
        onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
        persistDiagnostics: _persistLastAutomaticDiagnostics,
        pushDiagnostics: () => _pushDiagnosticsBestEffort(AutoUpdateDiagnosticsSource.reconcile),
      ),
    );
  }
}
