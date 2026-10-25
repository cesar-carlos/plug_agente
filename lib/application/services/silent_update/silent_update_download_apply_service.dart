import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show pid;
import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/auto_update_defaults.dart';
import 'package:plug_agente/application/services/auto_update_failure_messages.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/service_update_pending_coordinator.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_helper_launch_state.dart';
import 'package:plug_agente/application/services/silent_update/update_transition_gate.dart';
import 'package:plug_agente/application/services/silent_update_failure.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/versioning/app_version_comparator.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_appcast_probe_service.dart';
import 'package:result_dart/result_dart.dart';

typedef CloseApplicationForSilentUpdate = Future<void> Function({String? noticeTitle, String? noticeBody});

typedef CurrentProcessIdResolver = int Function();

sealed class PendingDownloadedResolution {
  const PendingDownloadedResolution();
}

final class PendingDownloadedNone extends PendingDownloadedResolution {
  const PendingDownloadedNone();
}

final class PendingDownloadedStaleCleared extends PendingDownloadedResolution {
  const PendingDownloadedStaleCleared();
}

final class PendingDownloadedInFlight extends PendingDownloadedResolution {
  const PendingDownloadedInFlight(this.pending);

  final PendingSilentUpdate pending;
}

final class PendingDownloadedReady extends PendingDownloadedResolution {
  const PendingDownloadedReady(this.pending);

  final PendingSilentUpdate pending;
}

final class PendingDownloadedAttention extends PendingDownloadedResolution {
  const PendingDownloadedAttention(this.pending);
  final PendingSilentUpdate pending;
}

sealed class SilentUpdateDownloadStageResult {
  const SilentUpdateDownloadStageResult();
}

final class SilentUpdateDownloadStageReady extends SilentUpdateDownloadStageResult {
  const SilentUpdateDownloadStageReady();
}

final class SilentUpdateDownloadStageFailure extends SilentUpdateDownloadStageResult {
  const SilentUpdateDownloadStageFailure(this.error);

  final Exception error;
}

final class SilentUpdateDownloadStageCancelled extends SilentUpdateDownloadStageResult {
  const SilentUpdateDownloadStageCancelled();
}

class SilentUpdateDownloadStageRequest {
  const SilentUpdateDownloadStageRequest({
    required this.probeResult,
    required this.remoteVersion,
    required this.cancelRequested,
    required this.automaticSilentUpdatesEnabled,
    required this.getDiagnostics,
    required this.onDiagnosticsUpdated,
    required this.persistDiagnostics,
    required this.notifyDiagnosticsChanged,
  });

  final AppcastProbeResult probeResult;
  final String remoteVersion;
  final bool Function() cancelRequested;
  final bool Function() automaticSilentUpdatesEnabled;
  final UpdateCheckDiagnostics? Function() getDiagnostics;
  final void Function(UpdateCheckDiagnostics?) onDiagnosticsUpdated;
  final Future<void> Function() persistDiagnostics;
  final void Function() notifyDiagnosticsChanged;
}

/// Download → stage → apply pending / helper launch logic extracted from the
/// silent update coordinator so the coordinator can delegate without
/// duplicating rules.
class SilentUpdateDownloadApplyService {
  SilentUpdateDownloadApplyService({
    required ISilentUpdateInstaller? installer,
    required IPendingSilentUpdateStore pendingStore,
    required PersistentCircuitBreaker automaticFailureBreaker,
    required ISilentUpdateLauncherStatusReader launcherStatusReader,
    this.servicePending,
    IUpdatePreferencesRepository? preferences,
    IAutoUpdateMetricsCollector? metricsCollector,
    CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
    CurrentProcessIdResolver? currentProcessIdResolver,
    Duration helperWaitDuration = AutoUpdateDefaults.helperWaitDuration,
    Duration stagedPendingTtl = AutoUpdateDefaults.stagedPendingTtl,
    DateTime Function()? clock,
  }) : _installer = installer,
       _pendingStore = pendingStore,
       _automaticFailureBreaker = automaticFailureBreaker,
       _launcherStatusReader = launcherStatusReader,
       _preferences = preferences,
       _metricsCollector = metricsCollector,
       _closeApplicationForSilentUpdate = closeApplicationForSilentUpdate,
       _currentProcessIdResolver = currentProcessIdResolver ?? (() => pid),
       _helperWaitDuration = helperWaitDuration,
       _stagedPendingTtl = stagedPendingTtl,
       _clock = clock ?? DateTime.now;

  final ISilentUpdateInstaller? _installer;
  final ServiceUpdatePendingCoordinator? servicePending;
  final IPendingSilentUpdateStore _pendingStore;
  final PersistentCircuitBreaker _automaticFailureBreaker;
  final ISilentUpdateLauncherStatusReader _launcherStatusReader;
  final IUpdatePreferencesRepository? _preferences;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final CloseApplicationForSilentUpdate? _closeApplicationForSilentUpdate;
  final CurrentProcessIdResolver _currentProcessIdResolver;
  final Duration _helperWaitDuration;
  final Duration _stagedPendingTtl;
  final DateTime Function() _clock;

  bool _applyInProgress = false;

  Future<void> cleanupArtifacts(ISilentUpdateInstaller installer) async {
    final cleanupResult = await installer.cleanupObsoleteArtifacts();
    cleanupResult.fold(
      (_) {},
      (error) {
        developer.log(
          'Silent update artifact cleanup failed',
          name: 'silent_update_download_apply',
          level: 900,
          error: error,
        );
      },
    );
  }

  Future<SilentUpdateDownloadStageResult> downloadAndStage(
    SilentUpdateDownloadStageRequest request,
  ) async {
    final installer = _installer;
    if (installer == null) {
      return SilentUpdateDownloadStageFailure(
        domain.ConfigurationFailure.withContext(
          message: 'Silent update installer is not configured',
          context: <String, dynamic>{'operation': 'downloadAndStage'},
        ),
      );
    }

    final downloadStart = _clock();
    final installResult = await installer.install(
      SilentUpdateInstallRequest(
        version: request.remoteVersion,
        assetUrl: request.probeResult.assetUrl!,
        assetSize: request.probeResult.assetSize!,
        assetName: request.probeResult.assetName!,
        sha256: request.probeResult.sha256!,
        requireValidSignature: resolveAutoUpdateRequireValidSignature(
          environment: AppEnvironment.snapshot(),
        ),
        cancelRequested: request.cancelRequested,
        allowDownloadResume: resolveAutoUpdateDownloadResume(
          environment: AppEnvironment.snapshot(),
        ),
        deferHelperLaunch: true,
        manifestUrl: request.probeResult.manifestUrl,
        manifestSha256: request.probeResult.manifestSha256,
        stageForService: installer is IServiceSilentUpdateInstaller,
      ),
    );
    try {
      _metricsCollector?.recordAutoUpdateDownloadDuration(_clock().difference(downloadStart));
    } on Object catch (error, stack) {
      developer.log('Download metrics unavailable', error: error, stackTrace: stack);
    }

    SilentUpdateInstallResult? installSuccess;
    Exception? installError;
    installResult.fold(
      (value) => installSuccess = value,
      (error) => installError = error,
    );

    final now = _clock();
    if (installError != null) {
      if (request.cancelRequested() && servicePending != null) {
        final reconciled = await servicePending!.reconcile(cancel: true);
        if (reconciled.isError()) return SilentUpdateDownloadStageFailure(reconciled.exceptionOrNull()!);
        final decision = reconciled.getOrThrow().decision;
        if (decision == ServicePendingDecision.active || decision == ServicePendingDecision.attention) {
          return SilentUpdateDownloadStageFailure(
            domain.ConfigurationFailure.withContext(
              message: 'O cancelamento ainda não foi confirmado. Verifique a recuperação.',
              context: const {'reason': 'cancellation_unconfirmed', 'outcome_unknown': true},
            ),
          );
        }
        return const SilentUpdateDownloadStageCancelled();
      }
      if (_isCancellationFailure(installError!)) {
        return const SilentUpdateDownloadStageCancelled();
      }
      if (servicePending == null || !isAutoUpdateDeferral(installError!)) await _pendingStore.clear();
      final completionSource = installError is domain.NetworkFailure
          ? UpdateCheckCompletionSource.automaticDownloadFailure
          : installError is domain.ValidationFailure
          ? UpdateCheckCompletionSource.automaticValidationFailure
          : UpdateCheckCompletionSource.automaticInstallFailure;
      final failureState = isAutoUpdateDeferral(installError!)
          ? PersistentCircuitBreakerState(
              failureCount: _automaticFailureBreaker.failureCount,
              cooldownUntil: _automaticFailureBreaker.cooldownUntil,
            )
          : await _automaticFailureBreaker.recordFailure();
      await _observeDiagnostics(() async {
        request.onDiagnosticsUpdated(
          request.getDiagnostics()?.copyWith(
            triggerCompletedAt: now,
            completedAt: now,
            completionSource: completionSource,
            automaticFailureCount: failureState.failureCount,
            automaticCooldownUntil: failureState.cooldownUntil,
            errorMessage: extractAutoUpdateFailureMessage(installError!),
          ),
        );
        await request.persistDiagnostics();
      });
      return SilentUpdateDownloadStageFailure(installError!);
    }

    final success = installSuccess!;
    await _pendingStore.write(
      success.strategy == SilentUpdateInstallStrategy.windowsService
          ? PendingSilentUpdateService(
              version: request.remoteVersion,
              startedAt: _clock(),
              operationId: success.serviceOperationId!,
            )
          : PendingSilentUpdateDownloaded(
              version: request.remoteVersion,
              startedAt: _clock(),
              installerPath: success.installerPath,
              logPath: success.logPath,
              installDirectory: success.installDirectory,
              strategy: success.strategy.name,
              serviceOperationId: success.serviceOperationId,
              launcherPath: success.launcherPath,
              launcherStatusPath: success.launcherStatusPath,
              appPid: success.appPid,
              assetSize: request.probeResult.assetSize,
              sha256: request.probeResult.sha256,
              requireValidSignature: resolveAutoUpdateRequireValidSignature(
                environment: AppEnvironment.snapshot(),
              ),
              installDirectoryWritable: success.installDirectoryWritable,
              updateDirectorySecurityStatus: success.updateDirectorySecurityStatus,
            ),
    );
    await _automaticFailureBreaker.reset();
    await _observeDiagnostics(() async {
      request.onDiagnosticsUpdated(
        request.getDiagnostics()?.copyWith(
          triggerCompletedAt: now,
          completedAt: now,
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
        ),
      );
      await request.persistDiagnostics();
    });

    if (request.cancelRequested()) {
      return const SilentUpdateDownloadStageCancelled();
    }

    // Preference turned off mid-flight after a successful stage: keep staged
    // Ready for manual banner/shutdown apply. Do not wipe useful artifacts.
    if (!request.automaticSilentUpdatesEnabled()) {
      await _observeDiagnostics(request.notifyDiagnosticsChanged);
    }

    return const SilentUpdateDownloadStageReady();
  }

  /// True when a staged update is Ready for a real apply: artifacts on disk,
  /// helper not in-flight, launch not already concluded/timed out, and within
  /// staged TTL. Read-only — clearing stale/expired records belongs to
  /// [resolvePersistedDownloadedPending] / reconcile, not banner polls.
  Future<bool> hasPendingDownloadedUpdate() async {
    final pending = await _pendingStore.read();
    if (pending is PendingSilentUpdateService && servicePending != null) {
      return servicePending!.isReady(pending);
    }
    if (pending is! PendingSilentUpdateDownloaded) return false;
    if (!await _artifactsExistOnDisk(pending)) return false;

    final now = _clock();
    final launcherStatus = await _launcherStatusReader.read(pending.launcherStatusPath);
    if (_isHelperInstallInFlight(pending, launcherStatus)) return false;
    if (SilentUpdateHelperLaunchState.isLaunchConcludedOrTimedOut(
      launchedAt: pending.launchedAt,
      launcherStatus: launcherStatus,
      now: now,
      helperWaitDuration: _helperWaitDuration,
    )) {
      return false;
    }
    if (SilentUpdateHelperLaunchState.isStagedPendingExpired(
      startedAt: pending.startedAt,
      now: now,
      stagedPendingTtl: _stagedPendingTtl,
    )) {
      return false;
    }
    return true;
  }

  Future<PendingDownloadedResolution> resolvePersistedDownloadedPending() =>
      UpdateTransitionGate.forStore(_pendingStore).run(_resolvePersistedDownloadedPending);

  Future<PendingDownloadedResolution> _resolvePersistedDownloadedPending() async {
    if (servicePending != null) {
      final result = await servicePending!.reconcile();
      if (result.isError()) throw result.exceptionOrNull()!;
      final resolved = result.getOrThrow();
      switch (resolved.decision) {
        case ServicePendingDecision.ready:
          return PendingDownloadedReady(resolved.pending!);
        case ServicePendingDecision.active:
          return PendingDownloadedInFlight(resolved.pending!);
        case ServicePendingDecision.attention:
          return PendingDownloadedAttention(resolved.pending!);
        case ServicePendingDecision.finished:
          return const PendingDownloadedStaleCleared();
        case ServicePendingDecision.none:
          return const PendingDownloadedNone();
      }
    }
    final pending = await _pendingStore.read();
    if (pending is! PendingSilentUpdateDownloaded) {
      return const PendingDownloadedNone();
    }

    final now = _clock();
    final launcherStatus = await _launcherStatusReader.read(pending.launcherStatusPath);
    if (_isHelperInstallInFlight(pending, launcherStatus)) {
      if (SilentUpdateHelperLaunchState.requiresRecovery(
        launchedAt: pending.launchedAt,
        launcherStatus: launcherStatus,
        now: now,
        helperWaitDuration: _helperWaitDuration,
      )) {
        return PendingDownloadedAttention(pending);
      }
      return PendingDownloadedInFlight(pending);
    }

    if (!await _artifactsExistOnDisk(pending)) {
      developer.log(
        'Clearing stale pending silent update (artifacts missing on disk): version=${pending.version}',
        name: 'silent_update_download_apply',
        level: 800,
      );
      await _pendingStore.clear();
      return const PendingDownloadedStaleCleared();
    }

    // Same fail+cooldown policy as PendingSilentUpdateReconciler: after a real
    // launch concludes or times out, never report Ready (would spawn a 2nd helper).
    if (SilentUpdateHelperLaunchState.isLaunchConcludedOrTimedOut(
      launchedAt: pending.launchedAt,
      launcherStatus: launcherStatus,
      now: now,
      helperWaitDuration: _helperWaitDuration,
    )) {
      developer.log(
        'Clearing pending silent update after launch concluded/timed out: version=${pending.version}',
        name: 'silent_update_download_apply',
        level: 800,
      );
      await _finalizeConcludedOrTimedOutPending(
        pending: pending,
        launcherStatus: launcherStatus,
      );
      return const PendingDownloadedStaleCleared();
    }

    if (SilentUpdateHelperLaunchState.isStagedPendingExpired(
      startedAt: pending.startedAt,
      now: now,
      stagedPendingTtl: _stagedPendingTtl,
    )) {
      developer.log(
        'Clearing staged pending silent update past TTL: version=${pending.version}',
        name: 'silent_update_download_apply',
        level: 800,
      );
      await _pendingStore.clear();
      final installer = _installer;
      if (installer != null) {
        await cleanupArtifacts(installer);
      }
      return const PendingDownloadedStaleCleared();
    }

    return PendingDownloadedReady(pending);
  }

  Future<bool> _artifactsExistOnDisk(PendingSilentUpdateDownloaded pending) async {
    final installerExists = await _launcherStatusReader.fileExists(pending.installerPath);
    final launcherExists = await _launcherStatusReader.fileExists(pending.launcherPath);
    return installerExists && launcherExists;
  }

  bool _isHelperInstallInFlight(
    PendingSilentUpdateDownloaded pending,
    SilentUpdateLauncherStatus? launcherStatus,
  ) {
    return SilentUpdateHelperLaunchState.isInFlight(
      launchedAt: pending.launchedAt,
      launcherStatus: launcherStatus,
      now: _clock(),
      helperWaitDuration: _helperWaitDuration,
    );
  }

  Future<void> _finalizeConcludedOrTimedOutPending({
    required PendingSilentUpdateDownloaded pending,
    required SilentUpdateLauncherStatus? launcherStatus,
  }) async {
    final resetBreaker = SilentUpdateHelperLaunchState.shouldResetBreakerForConcludedLaunch(
      versionCompleted: _isVersionCompleted(pending.version),
      launcherStatus: launcherStatus,
    );
    if (resetBreaker) {
      await _automaticFailureBreaker.reset();
    } else {
      await _automaticFailureBreaker.recordFailure();
    }
    await _pendingStore.clear();
    final installer = _installer;
    if (installer != null) {
      await cleanupArtifacts(installer);
    }
  }

  bool _isVersionCompleted(String pendingVersion) {
    try {
      return AppVersionComparator.compare(AppConstants.appVersion, pendingVersion) >= 0;
    } on FormatException {
      return false;
    }
  }

  Future<Result<void>> applyPendingDownloadedUpdate({
    required UpdateCheckDiagnostics? Function() getDiagnostics,
    required void Function(UpdateCheckDiagnostics?) onDiagnosticsUpdated,
    required Future<void> Function() persistDiagnostics,
    required void Function() notifyDiagnosticsChanged,
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    if (_applyInProgress) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'A atualização ainda está sendo preparada. Aguarde.',
          context: const {'reason': 'application_in_progress'},
        ),
      );
    }

    // Claim the guard synchronously, before the first `await` below. `await`
    // always yields to the event loop in Dart even when the awaited value is
    // already available, so claiming the guard any later (e.g. after reading
    // the pending record) leaves a window where a second call arriving in
    // between would see `_applyInProgress == false` too and race to launch
    // the helper twice. Every early-return path below resets the flag so a
    // genuine failure (no pending record, no installer, launch error, ...)
    // can still be retried.
    _applyInProgress = true;
    return UpdateTransitionGate.forStore(_pendingStore).run(() async {
      try {
        PendingSilentUpdate? pending;
        try {
          pending = await _pendingStore.read();
        } on Object catch (error) {
          _applyInProgress = false;
          return Failure(
            domain.ConfigurationFailure.withContext(
              message: 'Não foi possível consultar a operação de atualização. Tente novamente.',
              cause: error,
              context: const {'reason': 'pending_read_unconfirmed', 'outcome_unknown': true},
            ),
          );
        }
        if (pending == null) {
          _applyInProgress = false;
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
        final installer = _installer;
        if (installer == null) {
          _applyInProgress = false;
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
        if (pending is PendingSilentUpdateService) {
          try {
            if (installer is! IServiceSilentUpdateInstaller || servicePending == null) {
              return Failure(domain.ConfigurationFailure('O serviço de atualização exige nova preparação.'));
            }
            return await servicePending!.dispatch((resolved) async {
              final latest = await _pendingStore.read();
              if (latest is! PendingSilentUpdateService ||
                  latest.operationId != (pending! as PendingSilentUpdateService).operationId) {
                return Failure(domain.ConfigurationFailure('A operação de atualização mudou. Reconcilie novamente.'));
              }
              final serviceRecord = latest;
              if (serviceRecord.dispatchAttemptedAt == null && resolved.isError()) {
                return Failure(resolved.exceptionOrNull()!);
              }
              if (serviceRecord.dispatchAttemptedAt == null &&
                  resolved.getOrThrow().decision != ServicePendingDecision.ready) {
                return Failure(
                  domain.ConfigurationFailure('A operação de atualização precisa ser reconciliada antes de aplicar.'),
                );
              }
              final persisted = await _persistLaunchEvidence(
                serviceRecord,
                serviceRecord.copyWith(dispatchAttemptedAt: serviceRecord.dispatchAttemptedAt ?? _clock()),
              );
              if (persisted.isError()) return Failure(persisted.exceptionOrNull()!);
              final dispatched = await installer.launchServiceOperation(
                version: serviceRecord.version,
                operationId: serviceRecord.operationId,
                reconcileOnly: serviceRecord.dispatchAttemptedAt != null,
                appPid: _currentProcessIdResolver(),
              );
              if (dispatched.isError()) {
                final error = dispatched.exceptionOrNull()!;
                if (error is domain.Failure &&
                    (error.context['reason'] == 'maintenance_deferred' ||
                        (error.context['resources_closed'] == false && error.context['outcome_unknown'] != true))) {
                  await _pendingStore.write(serviceRecord.copyWith(clearDispatchAttempt: true));
                  await _preferences?.flushPendingPersistence();
                }
                try {
                  onDiagnosticsUpdated(
                    getDiagnostics()?.copyWith(
                      completedAt: _clock(),
                      errorMessage: extractAutoUpdateFailureMessage(dispatched.exceptionOrNull()!),
                    ),
                  );
                  await persistDiagnostics();
                  notifyDiagnosticsChanged();
                } on Object catch (diagnosticError, stack) {
                  developer.log(
                    'Dispatch failure retained; diagnostic persistence failed',
                    error: diagnosticError,
                    stackTrace: stack,
                  );
                }
                return Failure(dispatched.exceptionOrNull()!);
              }
              try {
                onDiagnosticsUpdated(
                  getDiagnostics()?.copyWith(
                    completedAt: _clock(),
                    completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
                  ),
                );
                await persistDiagnostics();
                notifyDiagnosticsChanged();
              } on Object catch (error, stack) {
                developer.log('Dispatch confirmed; diagnostic persistence failed', error: error, stackTrace: stack);
              }
              if (triggerAppClose) {
                _closeApplicationOrReportFailure(
                  noticeTitle: noticeTitle,
                  noticeBody: noticeBody,
                  getDiagnostics: getDiagnostics,
                  onDiagnosticsUpdated: onDiagnosticsUpdated,
                  persistDiagnostics: persistDiagnostics,
                  notifyDiagnosticsChanged: notifyDiagnosticsChanged,
                );
              }
              return const Success(unit);
            });
          } on Object catch (error) {
            return Failure(
              domain.ConfigurationFailure.withContext(
                message: 'A operação de atualização exige reconciliação. Tente novamente.',
                cause: error,
                context: const {'reason': 'service_application_unconfirmed', 'outcome_unknown': true},
              ),
            );
          } finally {
            _applyInProgress = false;
          }
        }
        if (pending is! PendingSilentUpdateDownloaded || !pending.hasFullApplyMetadata) {
          _applyInProgress = false;
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

        final launcherStatus = await _launcherStatusReader.read(pending.launcherStatusPath);
        if (SilentUpdateHelperLaunchState.requiresRecovery(
          launchedAt: pending.launchedAt,
          launcherStatus: launcherStatus,
          now: _clock(),
          helperWaitDuration: _helperWaitDuration,
        )) {
          _applyInProgress = false;
          return Failure(
            domain.ConfigurationFailure.withContext(
              message:
                  'O encerramento do instalador não foi confirmado. Verifique a recuperação antes de tentar novamente.',
              context: const {'operation': 'applyPendingDownloadedUpdate', 'reason': 'recovery_required'},
            ),
          );
        }
        if (_isHelperInstallInFlight(pending, launcherStatus)) {
          // Idempotent Success across process restarts: recent launchedAt / helper
          // status means a helper is already running — do not spawn a second one.
          _applyInProgress = false;
          if (triggerAppClose) {
            _closeApplicationOrReportFailure(
              noticeTitle: noticeTitle,
              noticeBody: noticeBody,
              getDiagnostics: getDiagnostics,
              onDiagnosticsUpdated: onDiagnosticsUpdated,
              persistDiagnostics: persistDiagnostics,
              notifyDiagnosticsChanged: notifyDiagnosticsChanged,
            );
          }
          return const Success(unit);
        }

        // Same gate as resolve: concluded/timed-out launch must never re-spawn.
        if (SilentUpdateHelperLaunchState.isLaunchConcludedOrTimedOut(
          launchedAt: pending.launchedAt,
          launcherStatus: launcherStatus,
          now: _clock(),
          helperWaitDuration: _helperWaitDuration,
        )) {
          final treatAsSuccess = SilentUpdateHelperLaunchState.shouldResetBreakerForConcludedLaunch(
            versionCompleted: _isVersionCompleted(pending.version),
            launcherStatus: launcherStatus,
          );
          developer.log(
            'Refusing apply after launch concluded/timed out: version=${pending.version}',
            name: 'silent_update_download_apply',
            level: 800,
          );
          await _finalizeConcludedOrTimedOutPending(
            pending: pending,
            launcherStatus: launcherStatus,
          );
          _applyInProgress = false;
          if (treatAsSuccess) {
            if (triggerAppClose) {
              _closeApplicationOrReportFailure(
                noticeTitle: noticeTitle,
                noticeBody: noticeBody,
                getDiagnostics: getDiagnostics,
                onDiagnosticsUpdated: onDiagnosticsUpdated,
                persistDiagnostics: persistDiagnostics,
                notifyDiagnosticsChanged: notifyDiagnosticsChanged,
              );
            }
            return const Success(unit);
          }
          return Failure(
            domain.ConfigurationFailure.withContext(
              message: 'Pending silent update launch already concluded or timed out',
              context: <String, dynamic>{
                'operation': 'applyPendingDownloadedUpdate',
                'reason': 'launch_concluded_or_timed_out',
                'version': pending.version,
              },
            ),
          );
        }

        // Persist launch evidence before spawn so a kill between Process.start and
        // the old post-spawn write cannot leave Ready with no launchedAt (reconcile
        // would re-apply). Flush so the stamp survives an immediate process death.
        final now = _clock();
        final pendingWithLaunch = pending.copyWith(launchedAt: now);
        final persisted = await _persistLaunchEvidence(pending, pendingWithLaunch);
        if (persisted.isError()) return Failure(persisted.exceptionOrNull()!);

        final launchResult = await installer.launchPreparedHelper(
          SilentUpdateLaunchRequest(
            version: pending.version,
            installerPath: pending.installerPath,
            logPath: pending.logPath,
            launcherPath: pending.launcherPath,
            launcherStatusPath: pending.launcherStatusPath,
            installDirectory: pending.installDirectory,
            assetSize: pending.assetSize!,
            sha256: pending.sha256!,
            installDirectoryWritable: pending.installDirectoryWritable!,
            requireValidSignature: pending.requireValidSignature!,
            appPid: _currentProcessIdResolver(),
            serviceOperationId: pending.serviceOperationId,
          ),
        );
        Exception? launchError;
        launchResult.fold(
          (_) {},
          (error) => launchError = error,
        );
        if (launchError != null) {
          // Roll back launch stamp so a failed spawn does not look in-flight for
          // the full helper wait window.
          if (launchError is! domain.Failure || (launchError! as domain.Failure).context['outcome_unknown'] != true) {
            await _pendingStore.write(pending.copyWith(clearLaunchedAt: true));
            await _preferences?.flushPendingPersistence();
          }
          _applyInProgress = false;
          return Failure(launchError!);
        }

        try {
          onDiagnosticsUpdated(
            getDiagnostics()?.copyWith(
              completedAt: now,
              completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
            ),
          );
          await persistDiagnostics();
          notifyDiagnosticsChanged();
        } on Object catch (error, stackTrace) {
          developer.log('Helper dispatch confirmed; diagnostics failed', error: error, stackTrace: stackTrace);
        }

        if (triggerAppClose) {
          _closeApplicationOrReportFailure(
            noticeTitle: noticeTitle,
            noticeBody: noticeBody,
            getDiagnostics: getDiagnostics,
            onDiagnosticsUpdated: onDiagnosticsUpdated,
            persistDiagnostics: persistDiagnostics,
            notifyDiagnosticsChanged: notifyDiagnosticsChanged,
          );
        }
        return const Success(unit);
      } on Object catch (error) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Não foi possível confirmar a atualização. Verifique a recuperação.',
            cause: error,
            context: const {'reason': 'application_unconfirmed', 'outcome_unknown': true},
          ),
        );
      } finally {
        _applyInProgress = false;
      }
    });
  }

  Future<void> _observeDiagnostics(FutureOr<void> Function() action) async {
    try {
      await action();
    } on Object catch (error, stack) {
      developer.log('Update diagnostics unavailable', error: error, stackTrace: stack);
    }
  }

  Future<Result<void>> _persistLaunchEvidence(
    PendingSilentUpdate previous,
    PendingSilentUpdate next,
  ) async {
    try {
      (await _pendingStore.save(next)).getOrThrow();
      await _preferences?.flushPendingPersistence();
      if (_preferences?.lastPersistError case final error?) {
        throw domain.ConfigurationFailure.withContext(
          message: 'Não foi possível salvar a atualização.',
          cause: error,
        );
      }
      return const Success(unit);
    } on Object catch (error) {
      // Nothing was dispatched. Restore readiness without erasing older evidence.
      Object? restoreError;
      try {
        (await _pendingStore.save(previous)).getOrThrow();
      } on Object catch (failure) {
        restoreError = failure;
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: restoreError == null
              ? 'Não foi possível salvar a operação. Tente novamente.'
              : 'Não foi possível restaurar o estado da atualização. Verifique o armazenamento.',
          cause: restoreError ?? error,
          context: {
            'reason': 'pending_persistence_unconfirmed',
            'resources_closed': false,
            'state_restored': restoreError == null,
          },
        ),
      );
    }
  }

  /// Fires the app-close callback without blocking the caller, but unlike a
  /// bare `unawaited(...)`, an exception here is never lost: the helper has
  /// already been launched and is waiting for this process to exit, so the
  /// operator needs to know the app failed to close on its own instead of
  /// staring at a UI stuck on "closing" forever.
  void _closeApplicationOrReportFailure({
    required String? noticeTitle,
    required String? noticeBody,
    required UpdateCheckDiagnostics? Function() getDiagnostics,
    required void Function(UpdateCheckDiagnostics?) onDiagnosticsUpdated,
    required Future<void> Function() persistDiagnostics,
    required void Function() notifyDiagnosticsChanged,
  }) {
    final closeApplication = _closeApplicationForSilentUpdate;
    if (closeApplication == null) return;
    unawaited(
      Future<void>.sync(() => closeApplication(noticeTitle: noticeTitle, noticeBody: noticeBody)).catchError((
        Object error,
        StackTrace stackTrace,
      ) async {
        // Helper already launched; reset so a later retry/UI path is not stuck
        // behind a permanent in-process apply guard while the process continues.
        _applyInProgress = false;
        developer.log(
          'Silent update failed to close the app for install; the helper is '
          'already launched and waiting for this process to exit',
          name: 'silent_update_download_apply',
          level: 900,
          error: error,
          stackTrace: stackTrace,
        );
        try {
          onDiagnosticsUpdated(
            getDiagnostics()?.copyWith(
              completedAt: _clock(),
              completionSource: UpdateCheckCompletionSource.automaticInstallFailure,
              errorMessage: 'Não foi possível fechar o aplicativo para concluir a atualização.',
            ),
          );
          await persistDiagnostics();
          notifyDiagnosticsChanged();
        } on Object catch (diagnosticError, diagnosticStack) {
          developer.log('Close failure diagnostics unavailable', error: diagnosticError, stackTrace: diagnosticStack);
        }
      }),
    );
  }

  bool _isCancellationFailure(Exception error) {
    if (error is SilentInstallCancellationFailure) return true;
    if (error is! domain.Failure) return false;
    return error.context[SilentInstallFailureContext.cancellationKey] == true;
  }
}
