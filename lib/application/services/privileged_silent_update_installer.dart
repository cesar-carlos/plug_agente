import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_privileged_updater.dart';
import 'package:plug_agente/domain/services/i_update_manifest_downloader.dart';
import 'package:plug_agente/domain/services/i_update_secrets_snapshot.dart';
import 'package:plug_agente/domain/services/silent_update_installer.dart';
import 'package:result_dart/result_dart.dart';

/// Uses the existing downloader; all privileged work is owned by the registered service.
/// Service failure never falls back to a UAC prompt or to the legacy helper.
class PrivilegedSilentUpdateInstaller implements IServiceSilentUpdateInstaller {
  PrivilegedSilentUpdateInstaller({
    required this.downloader,
    required this.manifests,
    required this.updater,
    required this.secrets,
    required this.prepareMaintenance,
    required this.dataDirectory,
    this.onRecoveryRequired,
    DateTime Function()? clock,
    Future<void> Function(Duration)? wait,
  }) : _clock = clock ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  final ISilentUpdateInstaller downloader;
  final IUpdateManifestDownloader manifests;
  @override
  final IPrivilegedUpdater updater;
  final IUpdateSecretsSnapshot secrets;
  final Future<Result<void>> Function(String operationId, {Future<Result<void>> Function()? beforeClose})
  prepareMaintenance;
  final Future<String> Function() dataDirectory;
  final void Function(bool unknown)? onRecoveryRequired;
  final Set<String> _closedOperations = {};
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _wait;

  domain.ConfigurationFailure _unavailable(String reason) => domain.ConfigurationFailure.withContext(
    message: 'A atualização automática foi adiada. Verifique o serviço de atualização.',
    context: {'reason': reason, 'resources_closed': false},
  );

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    try {
      final capabilities = await updater.capabilities();
      if (capabilities.isError()) return Failure(capabilities.exceptionOrNull()!);
      if (!capabilities.getOrThrow().canApplyAutomatically) return Failure(_unavailable('service_not_ready'));
      final url = request.manifestUrl;
      if (url == null || request.manifestSha256 == null || !request.deferHelperLaunch) {
        return Failure(_unavailable('manifest_required'));
      }
      final response = await manifests.download(url);
      if (response.isError()) return Failure(response.exceptionOrNull()!);
      final bytes = response.getOrThrow();
      if (sha256.convert(bytes).toString() != request.manifestSha256) {
        return Failure(_unavailable('manifest_hash_mismatch'));
      }
      final manifest = Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);
      final download = await downloader.install(request);
      if (download.isError()) return Failure(download.exceptionOrNull()!);
      final staged = download.getOrThrow();
      if (request.cancelRequested?.call() ?? false) return Failure(_unavailable('update_cancelled'));
      final prepared = await updater.prepare(manifest: manifest, installerPath: staged.installerPath);
      if (prepared.isError()) return Failure(prepared.exceptionOrNull()!);
      final status = prepared.getOrThrow();
      if (status.phase != UpdaterPhase.preparing || status.version != request.version || status.operationId == null) {
        return Failure(_unavailable('service_preparation_unconfirmed'));
      }
      return Success(
        SilentUpdateInstallResult(
          installerPath: staged.installerPath,
          logPath: staged.logPath,
          launcherPath: staged.launcherPath,
          launcherStatusPath: staged.launcherStatusPath,
          installDirectory: staged.installDirectory,
          strategy: SilentUpdateInstallStrategy.windowsService,
          installDirectoryWritable: false,
          appPid: staged.appPid,
          updateDirectorySecurityStatus: staged.updateDirectorySecurityStatus,
          serviceOperationId: status.operationId,
        ),
      );
    } on Object catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Não foi possível preparar a atualização pelo serviço.',
          cause: error,
          context: const {'reason': 'service_preparation_failed'},
        ),
      );
    }
  }

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) async {
    final operation = request.serviceOperationId;
    if (operation == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(operation)) {
      return Failure(_unavailable('service_operation_missing'));
    }
    return launchServiceOperation(version: request.version, operationId: operation, appPid: request.appPid);
  }

  @override
  Future<Result<void>> launchServiceOperation({
    required String version,
    required String operationId,
    required int appPid,
  }) async {
    final operation = operationId;
    if (_closedOperations.contains(operation)) {
      return await _reconcileDispatch(operation, version, appPid);
    }
    try {
      final capabilities = await updater.capabilities();
      if (capabilities.isError()) return Failure(capabilities.exceptionOrNull()!);
      if (!capabilities.getOrThrow().canApplyAutomatically) return Failure(_unavailable('service_not_ready'));
      final status = await updater.status();
      if (status.isError()) return Failure(status.exceptionOrNull()!);
      final current = status.getOrThrow();
      if (current.operationId != operation ||
          current.version != version ||
          !current.ownedByCaller ||
          current.phase != UpdaterPhase.preparing) {
        return Failure(_unavailable('service_operation_changed'));
      }
      final directory = await dataDirectory();
      String? encryptedSnapshot;
      final maintenance = await prepareMaintenance(
        operation,
        beforeClose: () async {
          final snapshot = await secrets.captureEncrypted();
          if (snapshot.isError()) return Failure(snapshot.exceptionOrNull()!);
          encryptedSnapshot = snapshot.getOrThrow();
          return const Success(unit);
        },
      );
      if (maintenance.isError()) {
        final error = maintenance.exceptionOrNull()!;
        if (error is domain.Failure && error.context['resources_closed'] == true) {
          _closedOperations.add(operation);
          return await _reconcileDispatch(operation, version, appPid, allowAcceptedUpdate: false);
        }
        return Failure(error);
      }
      _closedOperations.add(operation);
      if (encryptedSnapshot == null) {
        return await _reconcileDispatch(operation, version, appPid, allowAcceptedUpdate: false);
      }
      final started = await updater.start(
        operationId: operation,
        appPid: appPid,
        dataDirectory: directory,
        encryptedSecretsSnapshot: encryptedSnapshot!,
      );
      if (started.isError()) return await _reconcileDispatch(operation, version, appPid);
      final confirmation = started.getOrThrow();
      if (confirmation.status.operationId != operation || confirmation.status.phase != UpdaterPhase.waitingForExit) {
        return await _reconcileDispatch(operation, version, appPid);
      }
      return const Success(unit);
    } on Object catch (error) {
      if (_closedOperations.contains(operation)) {
        return await _reconcileDispatch(operation, version, appPid);
      }
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'A atualização exige recuperação. Consulte o serviço e tente novamente.',
          cause: error,
          context: const {'reason': 'service_dispatch_unconfirmed', 'outcome_unknown': true},
        ),
      );
    }
  }

  Future<Result<void>> _reconcileDispatch(
    String operation,
    String version,
    int appPid, {
    bool allowAcceptedUpdate = true,
  }) async {
    onRecoveryRequired?.call(true);
    final deadline = _clock().add(const Duration(minutes: 5));
    do {
      final result = await updater.status();
      if (result.isSuccess()) {
        final status = result.getOrThrow();
        if (status.operationId != operation || status.version != version || !status.ownedByCaller) break;
        if (allowAcceptedUpdate && status.active && !status.restartOnly) return const Success(unit);
        if (status.restartOnly && status.active) return const Success(unit);
        if (!status.active &&
            !status.requiresRecovery &&
            !status.finalizationPending &&
            (status.phase == UpdaterPhase.preparing || status.phase == UpdaterPhase.deferred)) {
          onRecoveryRequired?.call(false);
          final recovery = await updater.requestApplicationRecovery(operationId: operation, appPid: appPid);
          if (recovery.isSuccess()) {
            final confirmation = recovery.getOrThrow();
            if (confirmation.operationId == operation &&
                confirmation.restartOnly &&
                confirmation.phase == UpdaterPhase.waitingForExit) {
              return const Success(unit);
            }
          }
        }
      }
      await _wait(const Duration(seconds: 15));
    } while (_clock().isBefore(deadline));
    return Failure(
      domain.ConfigurationFailure.withContext(
        message: 'O agente está em recuperação. Verifique o serviço de atualização e tente reconciliar novamente.',
        context: {'reason': 'service_dispatch_unconfirmed', 'operation_id': operation, 'outcome_unknown': true},
      ),
    );
  }

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    final result = await updater.status();
    if (result.isError()) return Failure(result.exceptionOrNull()!);
    final status = result.getOrThrow();
    if (status.active ||
        status.requiresRecovery ||
        status.finalizationPending ||
        status.phase == UpdaterPhase.preparing) {
      return const Success(unit);
    }
    return downloader.cleanupObsoleteArtifacts();
  }
}
