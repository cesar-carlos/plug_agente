import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/observability/update_check_id_recorder.dart';
import 'package:plug_agente/application/services/auto_update_defaults.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_helper_launch_state.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';

class PendingSilentUpdateReconcileRequest {
  const PendingSilentUpdateReconcileRequest({
    required this.onDiagnosticsUpdated,
    required this.persistDiagnostics,
    required this.pushDiagnostics,
    required this.onCheckIdAssigned,
  });

  final void Function(UpdateCheckDiagnostics?) onDiagnosticsUpdated;
  final Future<void> Function() persistDiagnostics;
  final void Function() pushDiagnostics;
  final void Function(String? checkId) onCheckIdAssigned;
}

/// Reconciles a persisted pending silent-update record after a process
/// restart: stale cleanup, staged Ready retention, in-flight installer
/// retention, successful completion, or failure with circuit-breaker
/// accounting after a real helper launch.
class PendingSilentUpdateReconciler {
  PendingSilentUpdateReconciler({
    required IPendingSilentUpdateStore pendingStore,
    required ISilentUpdateLauncherStatusReader launcherStatusReader,
    required PersistentCircuitBreaker automaticFailureBreaker,
    required String? Function() feedUrlResolver,
    required UpdateCheckIdRecorder checkIdRecorder,
    Duration helperWaitDuration = AutoUpdateDefaults.helperWaitDuration,
    Duration stagedPendingTtl = AutoUpdateDefaults.stagedPendingTtl,
    DateTime Function()? clock,
  }) : _pendingStore = pendingStore,
       _launcherStatusReader = launcherStatusReader,
       _automaticFailureBreaker = automaticFailureBreaker,
       _feedUrlResolver = feedUrlResolver,
       _checkIdRecorder = checkIdRecorder,
       _helperWaitDuration = helperWaitDuration,
       _stagedPendingTtl = stagedPendingTtl,
       _clock = clock ?? DateTime.now;

  final IPendingSilentUpdateStore _pendingStore;
  final ISilentUpdateLauncherStatusReader _launcherStatusReader;
  final PersistentCircuitBreaker _automaticFailureBreaker;
  final String? Function() _feedUrlResolver;
  final UpdateCheckIdRecorder _checkIdRecorder;
  final Duration _helperWaitDuration;
  final Duration _stagedPendingTtl;
  final DateTime Function() _clock;

  Future<void> reconcile(PendingSilentUpdateReconcileRequest request) async {
    final pending = await _pendingStore.read();
    if (pending == null) return;
    final checkId = _checkIdRecorder.newId();
    request.onCheckIdAssigned(checkId);
    unawaited(_checkIdRecorder.record(checkId, source: 'reconcile'));
    final feedUrl = _feedUrlResolver() ?? officialAutoUpdateFeedUrl;
    final now = _clock();
    final downloaded = pending is PendingSilentUpdateDownloaded ? pending : null;
    final launcherStatusPath = downloaded?.launcherStatusPath;
    final launcherStatus = await _launcherStatusReader.read(launcherStatusPath);
    bool completed;
    try {
      completed = AppVersionComparator.compare(AppConstants.appVersion, pending.version) >= 0;
    } on FormatException {
      completed = false;
    }
    if (!completed && launcherStatus == null && await _isPendingStale(pending)) {
      developer.log(
        'Clearing stale pending silent update (paths no longer exist): version=${pending.version}',
        name: 'silent_update_coordinator',
        level: 800,
      );
      await _pendingStore.clear();
      request.pushDiagnostics();
      return;
    }

    final launchedAt = downloaded?.launchedAt;
    if (!completed &&
        SilentUpdateHelperLaunchState.isInFlight(
          launchedAt: launchedAt,
          launcherStatus: launcherStatus,
          now: now,
          helperWaitDuration: _helperWaitDuration,
        )) {
      request.onDiagnosticsUpdated(
        diagnosticsForPending(
          pending: pending,
          launcherStatus: launcherStatus,
          feedUrl: feedUrl,
          now: now,
          checkId: checkId,
          completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
          errorMessage: 'Silent update installer is still running',
          updateAvailable: true,
        ),
      );
      await request.persistDiagnostics();
      request.pushDiagnostics();
      return;
    }

    // Staged download without launch evidence must stay Ready for banner /
    // shutdown / auto-apply, unless past the staged TTL ops bound.
    if (!completed &&
        downloaded != null &&
        !SilentUpdateHelperLaunchState.hasLaunchEvidence(
          launchedAt: launchedAt,
          launcherStatus: launcherStatus,
        )) {
      if (SilentUpdateHelperLaunchState.isStagedPendingExpired(
        startedAt: downloaded.startedAt,
        now: now,
        stagedPendingTtl: _stagedPendingTtl,
      )) {
        developer.log(
          'Clearing staged pending silent update past TTL: version=${pending.version}',
          name: 'silent_update_coordinator',
          level: 800,
        );
        request.onDiagnosticsUpdated(
          diagnosticsForPending(
            pending: pending,
            launcherStatus: launcherStatus,
            feedUrl: feedUrl,
            now: now,
            checkId: checkId,
            completionSource: UpdateCheckCompletionSource.automaticPendingFailed,
            errorMessage: 'Staged silent update expired before it was applied',
          ),
        );
        await request.persistDiagnostics();
        await _pendingStore.clear();
        request.pushDiagnostics();
        return;
      }

      request.onDiagnosticsUpdated(
        diagnosticsForPending(
          pending: pending,
          launcherStatus: launcherStatus,
          feedUrl: feedUrl,
          now: now,
          checkId: checkId,
          completionSource: UpdateCheckCompletionSource.automaticInstallReady,
          updateAvailable: true,
        ),
      );
      await request.persistDiagnostics();
      request.pushDiagnostics();
      return;
    }

    // Unified with resolvePersistedDownloadedPending: launch evidence that is
    // no longer in-flight (helper wait elapsed or terminal status) clears and
    // fails (or completes) — never leaves Ready for an uncontrolled second launch.
    final resetBreaker = SilentUpdateHelperLaunchState.shouldResetBreakerForConcludedLaunch(
      versionCompleted: completed,
      launcherStatus: launcherStatus,
    );
    final failureState = resetBreaker ? null : await _automaticFailureBreaker.recordFailure();
    if (resetBreaker) {
      await _automaticFailureBreaker.reset();
    }
    request.onDiagnosticsUpdated(
      diagnosticsForPending(
        pending: pending,
        launcherStatus: launcherStatus,
        feedUrl: feedUrl,
        now: now,
        checkId: checkId,
        completionSource: completed
            ? UpdateCheckCompletionSource.automaticPendingCompleted
            : UpdateCheckCompletionSource.automaticPendingFailed,
        updateAvailable: !completed,
        automaticFailureCount: failureState?.failureCount,
        automaticCooldownUntil: failureState?.cooldownUntil,
        errorMessage: completed ? null : launcherStatus?.failureMessage ?? 'Pending silent update did not complete',
      ),
    );
    await request.persistDiagnostics();
    await _pendingStore.clear();
    request.pushDiagnostics();
  }

  static UpdateCheckDiagnostics diagnosticsForPending({
    required PendingSilentUpdate pending,
    required SilentUpdateLauncherStatus? launcherStatus,
    required String feedUrl,
    required DateTime now,
    required UpdateCheckCompletionSource completionSource,
    required String? checkId,
    bool updateAvailable = false,
    int? automaticFailureCount,
    DateTime? automaticCooldownUntil,
    String? errorMessage,
  }) {
    final downloaded = pending is PendingSilentUpdateDownloaded ? pending : null;
    return UpdateCheckDiagnostics(
      checkedAt: now,
      configuredFeedUrl: feedUrl,
      requestedFeedUrl: feedUrl,
      checkId: checkId,
      currentVersion: AppConstants.appVersion,
      completedAt: now,
      completionSource: completionSource,
      updateAvailable: updateAvailable,
      pendingVersion: pending.version,
      installerPath: launcherStatus?.installerPath ?? downloaded?.installerPath,
      installerLogPath: launcherStatus?.logPath ?? downloaded?.logPath,
      installDirectory: launcherStatus?.installDirectory ?? downloaded?.installDirectory,
      silentUpdateStrategy: launcherStatus?.strategy ?? downloaded?.strategy,
      launcherPath: downloaded?.launcherPath,
      launcherStatusPath: downloaded?.launcherStatusPath,
      launcherState: launcherStatus?.state,
      nonAdminExitCode: launcherStatus?.nonAdminExitCode,
      nonAdminDurationMs: launcherStatus?.nonAdminDurationMs,
      elevatedExitCode: launcherStatus?.elevatedExitCode,
      elevatedDurationMs: launcherStatus?.elevatedDurationMs,
      elevatedRetryStarted: launcherStatus?.elevatedRetryStarted,
      waitForAppExitDurationMs: launcherStatus?.waitForAppExitDurationMs,
      appPid: launcherStatus?.appPid ?? downloaded?.appPid,
      signatureStatus: launcherStatus?.signatureStatus,
      signatureRequired: launcherStatus?.signatureRequired,
      updateDirectorySecurityStatus: downloaded?.updateDirectorySecurityStatus,
      actualSha256: launcherStatus?.actualSha256,
      hashValidationStatus: launcherStatus?.hashValidationStatus,
      installDirectoryWritable: launcherStatus?.installDirectoryWritable,
      elevatedCancelled: launcherStatus?.elevatedCancelled,
      automaticFailureCount: automaticFailureCount,
      automaticCooldownUntil: automaticCooldownUntil,
      errorMessage: errorMessage,
    );
  }

  Future<bool> _isPendingStale(PendingSilentUpdate pending) async {
    if (pending is! PendingSilentUpdateDownloaded) return true;
    final installerMissing = !await _launcherStatusReader.fileExists(pending.installerPath);
    final launcherMissing = !await _launcherStatusReader.fileExists(pending.launcherPath);
    final statusMissing = !await _launcherStatusReader.fileExists(pending.launcherStatusPath);
    return installerMissing && launcherMissing && statusMissing;
  }
}
