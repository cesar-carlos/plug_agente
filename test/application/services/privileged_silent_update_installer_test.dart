import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/privileged_silent_update_installer.dart';
import 'package:plug_agente/application/services/service_update_pending_coordinator.dart';
import 'package:plug_agente/application/services/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/silent_update/silent_update_download_apply_service.dart';
import 'package:plug_agente/application/services/update_maintenance_admission.dart';
import 'package:plug_agente/application/services/update_maintenance_coordinator.dart';
import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_update_manifest_downloader.dart';
import 'package:plug_agente/domain/services/i_update_secrets_snapshot.dart';
import 'package:plug_agente/domain/services/silent_update_installer.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_repository.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';
import 'package:plug_agente/infrastructure/services/windows_privileged_updater.dart';
import 'package:result_dart/result_dart.dart';

const operation = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const version = '1.8.7+1';

class Downloader extends Fake implements ISilentUpdateInstaller {
  int downloads = 0;
  int launches = 0;

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    downloads++;
    expect(request.deferHelperLaunch, isTrue);
    return const Success(
      SilentUpdateInstallResult(
        installerPath: 'setup.exe',
        logPath: 'setup.log',
        launcherPath: 'helper.exe',
        launcherStatusPath: 'status.json',
        installDirectory: 'app',
        strategy: SilentUpdateInstallStrategy.elevatedOnly,
        installDirectoryWritable: false,
        appPid: 123,
        updateDirectorySecurityStatus: 'protected',
      ),
    );
  }

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) async {
    launches++;
    throw StateError('Legacy UAC helper must never execute');
  }
}

class ManifestDownloader extends Fake implements IUpdateManifestDownloader {
  final bytes = Uint8List.fromList(utf8.encode('{"signedEnvelope":"fixture"}'));
  @override
  Future<Result<Uint8List>> download(String url) async => Success(bytes);
}

class Secrets extends Fake implements IUpdateSecretsSnapshot {
  bool fail = false;
  int calls = 0;
  @override
  Future<Result<String>> captureEncrypted() async {
    calls++;
    return fail ? Failure(domain.ConfigurationFailure('Credenciais indisponíveis.')) : const Success('encrypted-dpapi');
  }
}

void main() {
  late Downloader downloader;
  late ManifestDownloader manifests;
  late Secrets secrets;
  late PrivilegedSilentUpdateInstaller installer;
  late List<String> commands;
  var ready = true;
  var rejectPrepare = false;
  var maintenanceCalls = 0;
  var maintenanceFails = false;
  var statusOperation = operation;
  var startState = 'waitingForExit';
  var nativeState = 'preparing';
  var communicationLost = false;
  var rejectStart = false;
  var loseStartReply = false;
  var recoveries = 0;
  var recoveryContract = 1;
  var now = DateTime(2026);
  final recoveryPhases = <bool>[];

  SilentUpdateInstallRequest request({String? digest}) => SilentUpdateInstallRequest(
    version: version,
    assetUrl: 'https://example.test/setup.exe',
    assetSize: 123,
    assetName: 'setup.exe',
    sha256: 'a' * 64,
    requireValidSignature: false,
    deferHelperLaunch: true,
    manifestUrl: 'https://example.test/manifest.json',
    manifestSha256: digest ?? sha256.convert(manifests.bytes).toString(),
  );
  SilentUpdateLaunchRequest launch({String? id = operation}) => SilentUpdateLaunchRequest(
    version: version,
    installerPath: 'setup.exe',
    logPath: 'setup.log',
    launcherPath: 'helper.exe',
    launcherStatusPath: 'status.json',
    installDirectory: 'app',
    assetSize: 123,
    sha256: 'a' * 64,
    installDirectoryWritable: false,
    requireValidSignature: false,
    appPid: 123,
    serviceOperationId: id,
  );

  setUp(() {
    downloader = Downloader();
    manifests = ManifestDownloader();
    secrets = Secrets();
    commands = [];
    ready = true;
    rejectPrepare = false;
    maintenanceCalls = 0;
    maintenanceFails = false;
    statusOperation = operation;
    startState = 'waitingForExit';
    nativeState = 'preparing';
    communicationLost = false;
    rejectStart = false;
    loseStartReply = false;
    recoveries = 0;
    recoveryContract = 1;
    now = DateTime(2026);
    recoveryPhases.clear();
    installer = PrivilegedSilentUpdateInstaller(
      clock: () => now,
      wait: (duration) async => now = now.add(duration),
      onRecoveryRequired: recoveryPhases.add,
      downloader: downloader,
      manifests: manifests,
      secrets: secrets,
      dataDirectory: () async => r'C:\ProgramData\PlugAgente',
      prepareMaintenance: (_, {beforeClose}) async {
        maintenanceCalls++;
        if (maintenanceFails) return Failure(domain.ConfigurationFailure('O agente está ocupado.'));
        return await beforeClose!();
      },
      updater: WindowsPrivilegedUpdater(
        requestTransport: (request) async {
          final command = request['command']! as String;
          commands.add(command);
          if (command == 'capabilities') {
            return Success({
              'capabilities': {
                'protocol': 1,
                'recoveryContract': recoveryContract,
                'authorized': ready,
                'applicationReady': ready,
                'channel': 'stable',
                'approved': const ['app.files'],
              },
            });
          }
          if (command == 'prepare' && rejectPrepare) {
            return Failure(
              domain.ConfigurationFailure.withContext(
                message: 'Manifesto rejeitado.',
                context: const {'reason': 'manifest_signature_invalid'},
              ),
            );
          }
          if (command == 'prepare') {
            expect(request['installerPath'], 'setup.exe');
            expect(request['manifest'], jsonDecode(utf8.decode(manifests.bytes)));
          }
          if (command == 'status' && communicationLost) {
            return Failure(domain.ConfigurationFailure('Serviço indisponível.'));
          }
          if (command == 'recoverApplication') {
            recoveries++;
            nativeState = 'waitingForExit';
          }
          if (command == 'start') {
            expect(request['appPid'], 123);
            expect(request['secretsSnapshot'], 'encrypted-dpapi');
            nativeState = rejectStart ? 'preparing' : startState;
            if (rejectStart || loseStartReply) {
              if (communicationLost) nativeState = 'preparing';
              return Failure(domain.ConfigurationFailure('Sem resposta de despacho.'));
            }
          }
          return Success({
            'status': {
              'protocol': 1,
              'state': command == 'prepare' ? 'preparing' : nativeState,
              'ownedByCaller': true,
              'restartOnly': recoveries > 0,
              'version': version,
              'operationId': statusOperation,
            },
            if (command == 'start') 'healthNonce': 'b' * 32,
          });
        },
      ),
    );
  });

  tearDown(() => expect(downloader.launches, 0));

  test('real pending maintenance SQLite and IPC recover after rejection without premature shutdown', () async {
    rejectStart = true;
    final directory = await Directory.systemTemp.createTemp('closed_update_recovery_');
    final database = AppDatabase(executor: NativeDatabase(File('${directory.path}/app.db')));
    final admission = UpdateMaintenanceAdmission();
    final repository = AgentActionRepository(database, maintenanceGate: admission);
    expect((await repository.listDefinitions()).isSuccess(), isTrue);
    Future<Result<void>> Function()? capture;
    var exits = 0;
    final maintenance = UpdateMaintenanceCoordinator(
      freezeAdmission: () => admission.transition(operation, UpdateMaintenancePhase.draining),
      restoreAdmission: () => admission.transition(operation, UpdateMaintenancePhase.operational),
      isSafelyIdle: () => admission.idle,
      applyExitPolicies: (_) async {
        return admission.internal(operation, () async {
          expect((await repository.listDefinitions()).isSuccess(), isTrue);
          exits++;
          return const Success(unit);
        });
      },
      beforeClose: () => capture!(),
      flushAndCloseLocalData: () async {
        admission.transition(operation, UpdateMaintenancePhase.resourcesClosed);
        await database.checkpointAndCloseForUpdate();
        return const Success(unit);
      },
    );
    installer = PrivilegedSilentUpdateInstaller(
      downloader: downloader,
      manifests: manifests,
      updater: installer.updater,
      secrets: secrets,
      dataDirectory: () async => directory.path,
      prepareMaintenance: (op, {beforeClose}) async {
        capture = beforeClose;
        final result = await maintenance.prepare(op);
        return result.fold((_) => const Success(unit), Failure.new);
      },
      onRecoveryRequired: (unknown) => admission.transition(
        operation,
        unknown ? UpdateMaintenancePhase.dispatchUnknown : UpdateMaintenancePhase.recoveryRequired,
      ),
    );
    final pending = InMemoryPendingSilentUpdateStore();
    await pending.write(
      PendingSilentUpdateService(version: version, startedAt: DateTime.now(), operationId: operation),
    );
    var appCloses = 0;
    final apply = SilentUpdateDownloadApplyService(
      installer: installer,
      pendingStore: pending,
      servicePending: ServiceUpdatePendingCoordinator(
        updater: installer.updater,
        store: pending,
        flush: () async {},
        clock: DateTime.now,
        stagedTtl: const Duration(days: 7),
      ),
      automaticFailureBreaker: PersistentCircuitBreaker(
        persistence: InMemoryCircuitBreakerPersistence(),
        threshold: 3,
        cooldown: const Duration(minutes: 15),
        logName: 'test',
      ),
      launcherStatusReader: const NoopSilentUpdateLauncherStatusReader(),
      closeApplicationForSilentUpdate: ({noticeTitle, noticeBody}) async {
        appCloses++;
      },
      currentProcessIdResolver: () => 123,
    );
    Future<Result<void>> dispatch() => apply.applyPendingDownloadedUpdate(
      getDiagnostics: () => null,
      onDiagnosticsUpdated: (_) {},
      persistDiagnostics: () async => throw StateError('diagnostic disk failure'),
      notifyDiagnosticsChanged: () {},
    );
    final first = dispatch();
    expect((await dispatch()).isError(), isTrue);
    expect(appCloses, 0);
    expect((await first).isSuccess(), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(appCloses, 1);
    expect(recoveries, 1);
    expect(exits, 1);
    expect(secrets.calls, 1);
    expect((await repository.listDefinitions()).exceptionOrNull().toString(), contains('manutenção'));
    expect((await pending.read() as PendingSilentUpdateService?)?.dispatchAttemptedAt, isNotNull);
    await admission.dispose();
    await directory.delete(recursive: true);
  });

  test('legacy supervisor blocks before maintenance', () async {
    recoveryContract = 0;
    expect((await installer.launchPreparedHelper(launch())).isError(), isTrue);
    expect(maintenanceCalls, 0);
  });

  test('accepted start with a lost reply reconciles without second dispatch', () async {
    loseStartReply = true;
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect(commands.where((c) => c == 'start'), hasLength(1));
    expect(maintenanceCalls, 1);
    expect(recoveries, 0);
  });

  test('confirmed rejection after closing requests only one recovery', () async {
    rejectStart = true;
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect(commands.where((c) => c == 'start'), hasLength(1));
    expect(recoveries, 1);
    expect(recoveryPhases, contains(false));
  });

  test('unknown outcome polls for five minutes and manual reconciliation never resends', () async {
    loseStartReply = true;
    // Only the first status read succeeds; dispatch loses communication.
    final originalUpdater = installer.updater;
    installer = PrivilegedSilentUpdateInstaller(
      downloader: downloader,
      manifests: manifests,
      updater: originalUpdater,
      secrets: secrets,
      dataDirectory: () async => 'data',
      prepareMaintenance: (_, {beforeClose}) async {
        maintenanceCalls++;
        communicationLost = true;
        return await beforeClose!();
      },
      clock: () => now,
      wait: (duration) async => now = now.add(duration),
      onRecoveryRequired: recoveryPhases.add,
    );
    final result = await installer.launchPreparedHelper(launch());
    expect(result.isError(), isTrue);
    expect(now, DateTime(2026).add(const Duration(minutes: 5)));
    expect(commands.where((c) => c == 'status'), hasLength(21));
    expect(recoveries, 0);
    communicationLost = false;
    nativeState = 'waitingForExit';
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect(commands.where((c) => c == 'start'), hasLength(1));
    expect(maintenanceCalls, 1);
  });

  test('unsigned executable is staged only after service authorizes a signed manifest', () async {
    final result = (await installer.install(request())).getOrThrow();
    expect(result.strategy, SilentUpdateInstallStrategy.windowsService);
    expect(result.serviceOperationId, operation);
    expect(commands, ['capabilities', 'prepare']);
    expect(downloader.downloads, 1);
  });
  test('unavailable service never falls back to the elevated helper', () async {
    ready = false;
    expect((await installer.install(request())).isError(), isTrue);
    expect((await installer.launchPreparedHelper(launch())).isError(), isTrue);
    expect(downloader.downloads, 0);
    expect(maintenanceCalls, 0);
  });
  test('manifest altered after feed verification is rejected before downloading installer', () async {
    expect((await installer.install(request(digest: '0' * 64))).isError(), isTrue);
    expect(downloader.downloads, 0);
    expect(commands, ['capabilities']);
  });
  test('service signature rejection is preserved without dispatch', () async {
    rejectPrepare = true;
    final failure = (await installer.install(request())).exceptionOrNull()! as domain.ConfigurationFailure;
    expect(failure.context['reason'], 'manifest_signature_invalid');
    expect(commands, isNot(contains('start')));
  });
  test('successful dispatch waits for maintenance and carries encrypted snapshot', () async {
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect(maintenanceCalls, 1);
    expect(commands, ['capabilities', 'status', 'start']);
    expect(secrets.calls, 1);
  });
  test('snapshot failure before closure restores admission without starting or restarting', () async {
    secrets.fail = true;
    expect((await installer.launchPreparedHelper(launch())).isError(), isTrue);
    expect(maintenanceCalls, 1);
    expect(recoveries, 0);
    expect(commands, isNot(contains('start')));
  });
  test('busy application defers without start', () async {
    maintenanceFails = true;
    expect((await installer.launchPreparedHelper(launch())).isError(), isTrue);
    expect(commands, isNot(contains('start')));
  });
  test('stale or missing operation cannot enter maintenance', () async {
    expect((await installer.launchPreparedHelper(launch(id: null))).isError(), isTrue);
    statusOperation = 'c' * 32;
    expect((await installer.launchPreparedHelper(launch())).isError(), isTrue);
    expect(maintenanceCalls, 0);
  });
  test('a response in the wrong phase reconciles rejection and restarts', () async {
    startState = 'preparing';
    expect((await installer.launchPreparedHelper(launch())).isSuccess(), isTrue);
    expect(recoveries, 1);
  });
}
