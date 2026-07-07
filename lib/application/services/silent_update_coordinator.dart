import 'dart:async';
import 'dart:ui' show VoidCallback;

import 'package:plug_agente/application/observability/i_auto_update_diagnostics_gateway.dart';
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_defaults.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/pending_silent_update_reconciler.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_collaborators.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_diagnostics_store.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_download_apply_service.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_probe_pipeline.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_scheduler.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/security/appcast_signature_verifier.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

export 'package:plug_agente/application/services/silent_update/silent_update_download_apply_service.dart'
    show CloseApplicationForSilentUpdate;

abstract interface class ISilentUpdateCoordinator {
  bool get isSilentCheckInProgress;
  bool get automaticSilentUpdatesEnabled;
  bool get automaticSilentUpdatesAutoApplyEnabled;
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

  /// Triggers the silent cycle (probe → validation → download → stage →
  /// optional auto-apply). The success bucket carries a [SilentUpdateOutcome]
  /// discriminating the reason the cycle ended.
  ///
  /// When auto-apply is enabled (default), a staged update is applied
  /// automatically after download without waiting for banner confirmation.
  /// Pass `userInitiated: true` from UI flows that require explicit
  /// operator confirmation before apply.
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
  }) : _collaborators = SilentUpdateCollaborators.create(
         capabilities: _capabilities,
         feedUrlResolver: _feedUrlResolver,
         appcastProbeService: appcastProbeService,
         silentUpdateInstaller: silentUpdateInstaller,
         settingsStore: settingsStore,
         updatePreferencesRepository: updatePreferencesRepository,
         closeApplicationForSilentUpdate: closeApplicationForSilentUpdate,
         onDiagnosticsChanged: onDiagnosticsChanged,
         automaticFailureCooldownThreshold: automaticFailureCooldownThreshold,
         automaticFailureCooldown: automaticFailureCooldown,
         helperWaitDuration: helperWaitDuration,
         bootJitterProvider: bootJitterProvider,
         signatureVerifier: signatureVerifier,
         checkIdRecorder: checkIdRecorder,
         metricsCollector: metricsCollector,
         diagnosticsGateway: diagnosticsGateway,
         uacDetector: uacDetector,
         pendingStore: pendingStore,
         launcherStatusReader: launcherStatusReader,
         diagnosticsStore: diagnosticsStore,
         scheduler: scheduler,
         downloadApplyService: downloadApplyService,
         pendingReconciler: pendingReconciler,
         clock: clock,
       ),
       _silentUpdateInstaller = silentUpdateInstaller {
    _collaborators.uacGuard.warnIfDetectorIsNoopOnSupportedRuntime();
    hydratePersistedDiagnostics();
  }

  static const String _defaultAutoApplyNoticeTitle = 'Plug Agente: update ready';
  static const String _defaultAutoApplyNoticeBody = 'Closing to install the update.';

  final RuntimeCapabilities _capabilities;
  final String? Function() _feedUrlResolver;
  final ISilentUpdateInstaller? _silentUpdateInstaller;
  final SilentUpdateCollaborators _collaborators;

  bool _isSilentCheckInProgress = false;
  bool _cancelRequested = false;
  String? _currentCheckId;

  SilentUpdateDiagnosticsStore get _diagnosticsStore => _collaborators.diagnosticsStore;

  UpdateCheckDiagnostics? get _lastAutomaticDiagnostics => _diagnosticsStore.lastAutomaticDiagnostics;

  set _lastAutomaticDiagnostics(UpdateCheckDiagnostics? value) {
    _diagnosticsStore.lastAutomaticDiagnostics = value;
  }

  @override
  bool get isSilentCheckInProgress => _isSilentCheckInProgress;

  @override
  bool get automaticSilentUpdatesEnabled => _collaborators.preferences.automaticSilentUpdatesEnabled;

  @override
  bool get automaticSilentUpdatesAutoApplyEnabled =>
      _collaborators.preferences.automaticSilentUpdatesAutoApplyEnabled;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => _diagnosticsStore.lastAutomaticDiagnostics;

  @override
  void hydratePersistedDiagnostics() => _diagnosticsStore.hydrate();

  @override
  Future<void> clearPersistedAutomaticDiagnostics() => _diagnosticsStore.clearPersisted();

  @override
  Future<void> reconcilePendingAndSchedule() async {
    await _reconcilePendingSilentUpdate();
    _collaborators.scheduler.stop();
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

    _currentCheckId = _collaborators.checkIdRecorder.newId();
    unawaited(_collaborators.checkIdRecorder.record(_currentCheckId!, source: 'silent'));

    if (!automaticSilentUpdatesEnabled) {
      return _completeEarlyCheck(
        feedUrl: feedUrl,
        outcome: const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.silentDisabled),
        completionSource: UpdateCheckCompletionSource.automaticDisabled,
      );
    }

    if (_collaborators.scheduler.isWithinQuietHours()) {
      return _completeEarlyCheck(
        feedUrl: feedUrl,
        outcome: const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.skippedByQuietHours),
        completionSource: UpdateCheckCompletionSource.automaticQuietHours,
      );
    }

    final installer = _silentUpdateInstaller;
    if (installer == null) {
      final now = _collaborators.clock();
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
      _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
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
      final pendingResolution = await _collaborators.downloadApplyService.resolvePersistedDownloadedPending();
      switch (pendingResolution) {
        case PendingDownloadedInFlight(:final pending):
          final now = _collaborators.clock();
          final launcherStatus = await _collaborators.launcherStatusReader.read(pending.launcherStatusPath);
          _lastAutomaticDiagnostics = PendingSilentUpdateReconciler.diagnosticsForPending(
            pending: pending,
            launcherStatus: launcherStatus,
            feedUrl: feedUrl,
            now: now,
            checkId: _currentCheckId,
            completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
            errorMessage: 'Silent update installer is still running',
            updateAvailable: true,
          );
          await _persistLastAutomaticDiagnostics();
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.pendingInProgress);
        case PendingDownloadedReady(:final pending):
          if (_shouldAutoApply() && !_cancelRequested) {
            return _autoApplyStagedUpdate(feedUrl: feedUrl);
          }
          return _returnInstallerReady(feedUrl: feedUrl, pending: pending);
        case PendingDownloadedNone():
        case PendingDownloadedStaleCleared():
          break;
      }

      await _collaborators.downloadApplyService.cleanupArtifacts(installer);
      final cooldownResult = await _collaborators.scheduler.buildCooldownResult(
        feedUrl: feedUrl,
        checkId: _currentCheckId,
        onDiagnostics: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
        persistDiagnostics: _persistLastAutomaticDiagnostics,
      );
      if (cooldownResult != null) {
        _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
        return cooldownResult;
      }

      final startedAt = _collaborators.clock();
      _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: startedAt,
        configuredFeedUrl: feedUrl,
        requestedFeedUrl: feedUrl,
        checkId: _currentCheckId,
        currentVersion: AppConstants.appVersion,
        probeRequestUrl: feedUrl,
      );
      await _persistLastAutomaticDiagnostics();

      final bucket = await _collaborators.rolloutBucketResolver.resolve();
      final probeDiagnostics = _lastAutomaticDiagnostics!;
      final probePipelineResult = await _collaborators.probePipeline.run(
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
            _collaborators.diagnosticsNotifier.notifyChanged();
          }
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          return outcome;
        case SilentUpdateProbeCancelled():
          final outcome = await _completeAutomaticCancellation(feedUrl);
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          return outcome;
        case SilentUpdateProbeProceedToDownload(
          probeResult: final probed,
          remoteVersion: final version,
        ):
          probeResult = probed;
          remoteVersion = version;
      }

      final stageResult = await _collaborators.downloadApplyService.downloadAndStage(
        SilentUpdateDownloadStageRequest(
          probeResult: probeResult,
          remoteVersion: remoteVersion,
          cancelRequested: () => _cancelRequested,
          automaticSilentUpdatesEnabled: () => automaticSilentUpdatesEnabled,
          getDiagnostics: () => _lastAutomaticDiagnostics,
          onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
          persistDiagnostics: _persistLastAutomaticDiagnostics,
          notifyDiagnosticsChanged: _collaborators.diagnosticsNotifier.notifyChanged,
        ),
      );
      switch (stageResult) {
        case SilentUpdateDownloadStageCancelled():
          final outcome = await _completeAutomaticCancellation(feedUrl);
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          return outcome;
        case SilentUpdateDownloadStageFailure(:final error):
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          return Failure<SilentUpdateOutcome, Exception>(error);
        case SilentUpdateDownloadStageDisabled():
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.silentDisabled);
        case SilentUpdateDownloadStageReady():
          _collaborators.diagnosticsNotifier.notifyChanged();
          _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
          if (_shouldAutoApply() && !_cancelRequested) {
            return _autoApplyStagedUpdate(feedUrl: feedUrl);
          }
          return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.installerReady);
      }
    } on FormatException catch (error) {
      final now = _collaborators.clock();
      final failureState = await _collaborators.automaticFailureBreaker.recordFailure();
      _lastAutomaticDiagnostics = _lastAutomaticDiagnostics?.copyWith(
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticValidationFailure,
        automaticFailureCount: failureState.failureCount,
        automaticCooldownUntil: failureState.cooldownUntil,
        errorMessage: error.message,
      );
      await _persistLastAutomaticDiagnostics();
      _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
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

  Future<Result<SilentUpdateOutcome>> _completeEarlyCheck({
    required String feedUrl,
    required Result<SilentUpdateOutcome> outcome,
    required UpdateCheckCompletionSource completionSource,
  }) async {
    final now = _collaborators.clock();
    _lastAutomaticDiagnostics = UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      checkId: _currentCheckId,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: completionSource,
      updateAvailable: false,
    );
    await _persistLastAutomaticDiagnostics();
    _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
    return outcome;
  }

  Future<Result<SilentUpdateOutcome>> _completeAutomaticCancellation(String feedUrl) {
    return _collaborators.cancellationHandler.completeAutomaticCancellation(
      feedUrl: feedUrl,
      checkId: _currentCheckId,
      existingDiagnostics: _lastAutomaticDiagnostics,
      onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
      persistDiagnostics: _persistLastAutomaticDiagnostics,
    );
  }

  @override
  void scheduleAndStart({bool runImmediately = true}) {
    _collaborators.scheduler.scheduleAndStart(
      runImmediately: runImmediately,
      onCheck: checkSilently,
    );
  }

  @override
  void stop() => _collaborators.scheduler.stop();

  @override
  void requestCancellation() {
    if (_isSilentCheckInProgress) {
      _cancelRequested = true;
    }
  }

  @override
  Future<bool> get hasPendingDownloadedUpdate => _collaborators.downloadApplyService.hasPendingDownloadedUpdate();

  @override
  Future<Result<void>> applyPendingDownloadedUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) {
    return _collaborators.downloadApplyService.applyPendingDownloadedUpdate(
      noticeTitle: noticeTitle,
      noticeBody: noticeBody,
      triggerAppClose: triggerAppClose,
      getDiagnostics: () => _lastAutomaticDiagnostics,
      onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
      persistDiagnostics: _persistLastAutomaticDiagnostics,
      notifyDiagnosticsChanged: _collaborators.diagnosticsNotifier.notifyChanged,
    );
  }

  Future<void> _persistLastAutomaticDiagnostics() => _diagnosticsStore.persist();

  Future<void> _reconcilePendingSilentUpdate() async {
    await _collaborators.pendingReconciler.reconcile(
      PendingSilentUpdateReconcileRequest(
        onCheckIdAssigned: (checkId) => _currentCheckId = checkId,
        onDiagnosticsUpdated: (diagnostics) => _lastAutomaticDiagnostics = diagnostics,
        persistDiagnostics: _persistLastAutomaticDiagnostics,
        pushDiagnostics: () => _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.reconcile),
      ),
    );
  }

  bool _shouldAutoApply() {
    return shouldAutoApplySilentUpdate(
      automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
      automaticSilentUpdatesAutoApplyEnabled: automaticSilentUpdatesAutoApplyEnabled,
      environment: AppEnvironment.snapshot(),
    );
  }

  Future<Result<SilentUpdateOutcome>> _returnInstallerReady({
    required String feedUrl,
    required PendingSilentUpdateDownloaded pending,
  }) async {
    final now = _collaborators.clock();
    final launcherStatus = await _collaborators.launcherStatusReader.read(pending.launcherStatusPath);
    _lastAutomaticDiagnostics = PendingSilentUpdateReconciler.diagnosticsForPending(
      pending: pending,
      launcherStatus: launcherStatus,
      feedUrl: feedUrl,
      now: now,
      checkId: _currentCheckId,
      completionSource: UpdateCheckCompletionSource.automaticInstallReady,
      updateAvailable: true,
    );
    await _persistLastAutomaticDiagnostics();
    _collaborators.diagnosticsNotifier.notifyChanged();
    _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
    return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.installerReady);
  }

  Future<Result<SilentUpdateOutcome>> _autoApplyStagedUpdate({required String feedUrl}) async {
    if (!automaticSilentUpdatesEnabled || _cancelRequested) {
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.installerReady);
    }

    final applyResult = await applyPendingDownloadedUpdate(
      noticeTitle: _defaultAutoApplyNoticeTitle,
      noticeBody: _defaultAutoApplyNoticeBody,
    );
    Exception? applyError;
    applyResult.fold(
      (_) {},
      (error) => applyError = error,
    );
    if (applyError == null) {
      _collaborators.metricsCollector?.recordAutoUpdateAutomaticApplySuccess();
      _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
      return const Success<SilentUpdateOutcome, Exception>(SilentUpdateOutcome.installerReady);
    }

    _collaborators.metricsCollector?.recordAutoUpdateAutomaticApplyFailure();
    _collaborators.diagnosticsNotifier.pushBestEffort(AutoUpdateDiagnosticsSource.silent);
    final pending = await _collaborators.pendingStore.read();
    if (pending is PendingSilentUpdateDownloaded) {
      return _returnInstallerReady(feedUrl: feedUrl, pending: pending);
    }
    return Failure<SilentUpdateOutcome, Exception>(applyError!);
  }

}
