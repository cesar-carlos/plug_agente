import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/application/observability/i_auto_update_metrics_collector.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_failure_messages.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_failure.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

typedef CloseApplicationForSilentUpdate = Future<void> Function({String? noticeTitle, String? noticeBody});

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

final class SilentUpdateDownloadStageDisabled extends SilentUpdateDownloadStageResult {
  const SilentUpdateDownloadStageDisabled();
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
    IUpdatePreferencesRepository? preferences,
    IAutoUpdateMetricsCollector? metricsCollector,
    CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
    DateTime Function()? clock,
  }) : _installer = installer,
       _pendingStore = pendingStore,
       _automaticFailureBreaker = automaticFailureBreaker,
       _launcherStatusReader = launcherStatusReader,
       _preferences = preferences,
       _metricsCollector = metricsCollector,
       _closeApplicationForSilentUpdate = closeApplicationForSilentUpdate,
       _clock = clock ?? DateTime.now;

  final ISilentUpdateInstaller? _installer;
  final IPendingSilentUpdateStore _pendingStore;
  final PersistentCircuitBreaker _automaticFailureBreaker;
  final ISilentUpdateLauncherStatusReader _launcherStatusReader;
  final IUpdatePreferencesRepository? _preferences;
  final IAutoUpdateMetricsCollector? _metricsCollector;
  final CloseApplicationForSilentUpdate? _closeApplicationForSilentUpdate;
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
      ),
    );
    _metricsCollector?.recordAutoUpdateDownloadDuration(_clock().difference(downloadStart));

    SilentUpdateInstallResult? installSuccess;
    Exception? installError;
    installResult.fold(
      (value) => installSuccess = value,
      (error) => installError = error,
    );

    final now = _clock();
    if (installError != null) {
      if (_isCancellationFailure(installError!)) {
        return const SilentUpdateDownloadStageCancelled();
      }
      await _pendingStore.clear();
      final completionSource = installError is domain.NetworkFailure
          ? UpdateCheckCompletionSource.automaticDownloadFailure
          : installError is domain.ValidationFailure
          ? UpdateCheckCompletionSource.automaticValidationFailure
          : UpdateCheckCompletionSource.automaticInstallFailure;
      final failureState = await _automaticFailureBreaker.recordFailure();
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
      return SilentUpdateDownloadStageFailure(installError!);
    }

    final success = installSuccess!;
    await _pendingStore.write(
      PendingSilentUpdateDownloaded(
        version: request.remoteVersion,
        startedAt: _clock(),
        installerPath: success.installerPath,
        logPath: success.logPath,
        installDirectory: success.installDirectory,
        strategy: success.strategy.name,
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
    await _preferences?.flushPendingPersistence();

    if (request.cancelRequested()) {
      return const SilentUpdateDownloadStageCancelled();
    }

    if (!request.automaticSilentUpdatesEnabled()) {
      await _pendingStore.clear();
      final disabledAt = _clock();
      request.onDiagnosticsUpdated(
        request.getDiagnostics()?.copyWith(
          completedAt: disabledAt,
          completionSource: UpdateCheckCompletionSource.automaticDisabled,
          updateAvailable: false,
        ),
      );
      await request.persistDiagnostics();
      request.notifyDiagnosticsChanged();
      return const SilentUpdateDownloadStageDisabled();
    }

    return const SilentUpdateDownloadStageReady();
  }

  Future<bool> hasPendingDownloadedUpdate() async {
    final pending = await _pendingStore.read();
    if (pending is! PendingSilentUpdateDownloaded) return false;
    final installerExists = await _launcherStatusReader.fileExists(pending.installerPath);
    final launcherExists = await _launcherStatusReader.fileExists(pending.launcherPath);
    return installerExists && launcherExists;
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
    final pending = await _pendingStore.read();
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
    final installer = _installer;
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
    if (pending is! PendingSilentUpdateDownloaded || !pending.hasFullApplyMetadata) {
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
        installerPath: pending.installerPath,
        logPath: pending.logPath,
        launcherPath: pending.launcherPath,
        launcherStatusPath: pending.launcherStatusPath,
        installDirectory: pending.installDirectory,
        assetSize: pending.assetSize!,
        sha256: pending.sha256!,
        installDirectoryWritable: pending.installDirectoryWritable!,
        requireValidSignature: pending.requireValidSignature!,
        appPid: pending.appPid,
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
    _applyInProgress = true;

    final now = _clock();
    onDiagnosticsUpdated(
      getDiagnostics()?.copyWith(
        completedAt: now,
        completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
      ),
    );
    await persistDiagnostics();
    notifyDiagnosticsChanged();

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

  bool _isCancellationFailure(Exception error) {
    if (error is SilentInstallCancellationFailure) return true;
    if (error is! domain.Failure) return false;
    return error.context[SilentInstallFailureContext.cancellationKey] == true;
  }
}
