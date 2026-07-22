import 'dart:async';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/i_circuit_breaker_persistence.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/application/services/persistent_circuit_breaker.dart';
import 'package:plug_agente/application/services/silent_update_download_apply_service.dart';
import 'package:plug_agente/application/services/silent_update_failure.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

import '../../helpers/auto_update_test_fakes.dart';

class FakeLauncherStatusReader implements ISilentUpdateLauncherStatusReader {
  final Set<String> existingPaths = <String>{};

  @override
  Future<bool> fileExists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return existingPaths.contains(path);
  }

  @override
  Future<SilentUpdateLauncherStatus?> read(String? statusPath) async => null;
}

SilentUpdateDownloadApplyService _makeService({
  FakeSilentUpdateInstaller? installer,
  FakePendingSilentUpdateStore? pendingStore,
  ISilentUpdateLauncherStatusReader? launcherStatusReader,
  PersistentCircuitBreaker? automaticFailureBreaker,
  CloseApplicationForSilentUpdate? closeApplicationForSilentUpdate,
  DateTime Function()? clock,
  CurrentProcessIdResolver? currentProcessIdResolver,
}) {
  return SilentUpdateDownloadApplyService(
    installer: installer,
    pendingStore: pendingStore ?? FakePendingSilentUpdateStore(),
    automaticFailureBreaker:
        automaticFailureBreaker ??
        PersistentCircuitBreaker(
          persistence: InMemoryCircuitBreakerPersistence(),
          threshold: 3,
          cooldown: const Duration(minutes: 5),
          logName: 'silent_update_download_apply_test',
          clock: clock ?? (() => DateTime.utc(2026, 6, 10, 12)),
        ),
    launcherStatusReader: launcherStatusReader ?? FakeLauncherStatusReader(),
    closeApplicationForSilentUpdate: closeApplicationForSilentUpdate,
    clock: clock ?? (() => DateTime.utc(2026, 6, 10, 12)),
    currentProcessIdResolver: currentProcessIdResolver,
  );
}

AppcastProbeResult _probeResult() {
  return const AppcastProbeResult(
    requestUrl: 'https://example.com/appcast.xml',
    latestVersion: '99.0.0+1',
    assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
    assetSize: 5,
    assetName: 'PlugAgente-Setup-99.0.0.exe',
    sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    itemCount: 1,
  );
}

PendingSilentUpdateDownloaded _downloadedPending({
  String version = '99.0.0+1',
  bool fullMetadata = true,
}) {
  return PendingSilentUpdateDownloaded(
    version: version,
    startedAt: DateTime.utc(2026, 6, 10, 12),
    installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
    logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
    launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
    launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
    installDirectory: r'C:\PlugAgente',
    strategy: 'currentUserThenElevated',
    appPid: 1234,
    assetSize: fullMetadata ? 5 : null,
    sha256: fullMetadata ? '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824' : null,
    installDirectoryWritable: fullMetadata ? true : null,
    requireValidSignature: fullMetadata ? false : null,
    updateDirectorySecurityStatus: 'restricted',
  );
}

void main() {
  setUpAll(() {
    dotenv.clean();
    dotenv.loadFromString(
      envString:
          'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
          'AUTO_UPDATE_CHECK_INTERVAL_SECONDS=3600',
    );
  });

  group('SilentUpdateDownloadApplyService', () {
    late FakeSilentUpdateInstaller installer;
    late FakePendingSilentUpdateStore pendingStore;
    late FakeLauncherStatusReader launcherStatusReader;
    late PersistentCircuitBreaker breaker;
    late SilentUpdateDownloadApplyService service;
    UpdateCheckDiagnostics? latestDiagnostics;
    var persistCount = 0;
    var notifyCount = 0;

    SilentUpdateDownloadStageRequest stageRequest({
      AppcastProbeResult? probeResult,
      String remoteVersion = '99.0.0+1',
      bool Function()? cancelRequested,
      bool Function()? automaticSilentUpdatesEnabled,
    }) {
      return SilentUpdateDownloadStageRequest(
        probeResult: probeResult ?? _probeResult(),
        remoteVersion: remoteVersion,
        cancelRequested: cancelRequested ?? () => false,
        automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled ?? () => true,
        getDiagnostics: () => latestDiagnostics,
        onDiagnosticsUpdated: (diagnostics) => latestDiagnostics = diagnostics,
        persistDiagnostics: () async {
          persistCount++;
        },
        notifyDiagnosticsChanged: () {
          notifyCount++;
        },
      );
    }

    setUp(() {
      installer = FakeSilentUpdateInstaller();
      pendingStore = FakePendingSilentUpdateStore();
      launcherStatusReader = FakeLauncherStatusReader();
      breaker = PersistentCircuitBreaker(
        persistence: InMemoryCircuitBreakerPersistence(),
        threshold: 3,
        cooldown: const Duration(minutes: 5),
        logName: 'silent_update_download_apply_test',
        clock: () => DateTime.utc(2026, 6, 10, 12),
      );
      service = _makeService(
        installer: installer,
        pendingStore: pendingStore,
        launcherStatusReader: launcherStatusReader,
        automaticFailureBreaker: breaker,
      );
      latestDiagnostics = UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026, 6, 10, 12),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml',
        currentVersion: '1.0.0+1',
      );
      persistCount = 0;
      notifyCount = 0;
    });

    group('downloadAndStage', () {
      test('returns Ready on successful install and persists pending record', () async {
        final result = await service.downloadAndStage(stageRequest());

        expect(result, isA<SilentUpdateDownloadStageReady>());
        expect(installer.installCount, 1);
        expect(installer.request?.deferHelperLaunch, isTrue);
        expect(pendingStore.writeCount, 1);
        expect(pendingStore.pending, isA<PendingSilentUpdateDownloaded>());
        expect(
          (pendingStore.pending! as PendingSilentUpdateDownloaded).version,
          '99.0.0+1',
        );
        expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticInstallReady);
        expect(persistCount, greaterThan(0));
        expect(breaker.failureCount, 0);
      });

      test('returns Failure on install error, clears pending and records breaker failure', () async {
        installer.result = Failure(
          domain.NetworkFailure.withContext(
            message: 'download failed',
            context: <String, dynamic>{'operation': 'silentUpdateInstall'},
          ),
        );

        final result = await service.downloadAndStage(stageRequest());

        expect(result, isA<SilentUpdateDownloadStageFailure>());
        final failure = (result as SilentUpdateDownloadStageFailure).error;
        expect(failure, isA<domain.NetworkFailure>());
        expect(pendingStore.clearCount, 1);
        expect(pendingStore.pending, isNull);
        expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticDownloadFailure);
        expect(latestDiagnostics?.automaticFailureCount, 1);
        expect(breaker.failureCount, 1);
      });

      test('maps validation failures to automaticValidationFailure completion source', () async {
        installer.result = Failure(
          domain.ValidationFailure.withContext(
            message: 'hash mismatch',
            context: <String, dynamic>{'operation': 'silentUpdateInstall'},
          ),
        );

        final result = await service.downloadAndStage(stageRequest());

        expect(result, isA<SilentUpdateDownloadStageFailure>());
        expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticValidationFailure);
      });

      test('returns Cancelled when installer reports cancellation failure', () async {
        installer.result = Failure(
          SilentInstallCancellationFailure(message: 'cancelled mid-download'),
        );

        final result = await service.downloadAndStage(stageRequest());

        expect(result, isA<SilentUpdateDownloadStageCancelled>());
        expect(pendingStore.clearCount, 0);
        expect(breaker.failureCount, 0);
      });

      test('returns Cancelled when cancelRequested is true after staging', () async {
        var cancelled = false;
        installer.onBeforeReturn = () async {
          cancelled = true;
        };

        final result = await service.downloadAndStage(
          stageRequest(cancelRequested: () => cancelled),
        );

        expect(result, isA<SilentUpdateDownloadStageCancelled>());
        expect(pendingStore.writeCount, 1);
      });

      test('keeps staged Ready when automatic silent updates are off after staging', () async {
        var disabled = false;
        installer.onBeforeReturn = () async {
          disabled = true;
        };

        final result = await service.downloadAndStage(
          stageRequest(
            automaticSilentUpdatesEnabled: () => !disabled,
          ),
        );

        expect(result, isA<SilentUpdateDownloadStageReady>());
        expect(pendingStore.clearCount, 0);
        expect(pendingStore.pending, isA<PendingSilentUpdateDownloaded>());
        expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticInstallReady);
        expect(notifyCount, 1);
      });

      test('returns Failure when installer is not configured', () async {
        final unconfigured = _makeService();

        final result = await unconfigured.downloadAndStage(stageRequest());

        expect(result, isA<SilentUpdateDownloadStageFailure>());
        expect((result as SilentUpdateDownloadStageFailure).error, isA<domain.ConfigurationFailure>());
      });
    });

    group('hasPendingDownloadedUpdate', () {
      test('returns false when store is empty', () async {
        expect(await service.hasPendingDownloadedUpdate(), isFalse);
      });

      test('returns false for probed-only pending record', () async {
        pendingStore.pending = const PendingSilentUpdateProbed(
          version: '99.0.0+1',
          startedAt: null,
        );

        expect(await service.hasPendingDownloadedUpdate(), isFalse);
      });

      test('returns true when installer and launcher paths exist', () async {
        final pending = _downloadedPending();
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        expect(await service.hasPendingDownloadedUpdate(), isTrue);
      });

      test('returns false when helper is in-flight despite artifacts on disk', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 11, 50),
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        expect(await service.hasPendingDownloadedUpdate(), isFalse);
      });

      test('returns false when staged files are missing on disk', () async {
        pendingStore.pending = _downloadedPending();

        expect(await service.hasPendingDownloadedUpdate(), isFalse);
      });

      test('returns false when only installer path exists', () async {
        final pending = _downloadedPending();
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths.add(pending.installerPath);

        expect(await service.hasPendingDownloadedUpdate(), isFalse);
      });
    });

    group('resolvePersistedDownloadedPending', () {
      test('returns none when store is empty', () async {
        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedNone>());
      });

      test('clears stale pending when artifacts are missing', () async {
        pendingStore.pending = _downloadedPending();

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedStaleCleared>());
        expect(pendingStore.clearCount, 1);
        expect(pendingStore.pending, isNull);
      });

      test('returns ready when artifacts exist and helper is not in flight', () async {
        final pending = PendingSilentUpdateDownloaded(
          version: '99.0.0+1',
          startedAt: DateTime.utc(2026, 6, 10, 10),
          installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
          logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
          launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
          installDirectory: r'C:\PlugAgente',
          strategy: 'currentUserThenElevated',
          appPid: 1234,
          assetSize: 5,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          installDirectoryWritable: true,
          requireValidSignature: false,
          updateDirectorySecurityStatus: 'restricted',
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedReady>());
        expect((resolution as PendingDownloadedReady).pending.version, '99.0.0+1');
      });

      test('returns ready for staged download with recent startedAt and no status file', () async {
        final pending = _downloadedPending();
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedReady>());
      });

      test('returns ready for staged download with old startedAt within TTL and no status file', () async {
        final pending = PendingSilentUpdateDownloaded(
          version: '99.0.0+1',
          startedAt: DateTime.utc(2026, 6, 10, 8),
          installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
          logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
          launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
          installDirectory: r'C:\PlugAgente',
          strategy: 'currentUserThenElevated',
          appPid: 1234,
          assetSize: 5,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          installDirectoryWritable: true,
          requireValidSignature: false,
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedReady>());
      });

      test('returns inFlight when helper status indicates active install', () async {
        final pending = _downloadedPending();
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          launcherStatusReader: _InFlightLauncherStatusReader(
            pending: pending,
            lastUpdatedAt: DateTime.utc(2026, 6, 10, 12, 5),
          ),
          automaticFailureBreaker: breaker,
          clock: () => DateTime.utc(2026, 6, 10, 12, 10),
        );

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedInFlight>());
      });

      test('returns inFlight when launchedAt is recent even without status file', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 11, 50),
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedInFlight>());
      });

      test('clears and returns stale when launchedAt is outside helper wait without status', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedStaleCleared>());
        expect(pendingStore.clearCount, 1);
        expect(pendingStore.pending, isNull);
        expect(breaker.failureCount, 1);
      });

      test('resets breaker on terminal helper success even when app version is still older', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);
        await breaker.recordFailure();
        await breaker.recordFailure();

        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          launcherStatusReader: _TerminalLauncherStatusReader(
            pending: pending,
            state: 'completed',
            lastUpdatedAt: DateTime.utc(2026, 6, 10, 10),
          ),
          automaticFailureBreaker: breaker,
          clock: () => DateTime.utc(2026, 6, 10, 12),
        );

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedStaleCleared>());
        expect(pendingStore.pending, isNull);
        expect(
          breaker.failureCount,
          0,
          reason: 'terminal success must reset breaker (parity with reconcile)',
        );
      });

      test('clears staged pending past TTL', () async {
        final pending = PendingSilentUpdateDownloaded(
          version: '99.0.0+1',
          startedAt: DateTime.utc(2026, 6, 1, 12),
          installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
          logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
          launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
          installDirectory: r'C:\PlugAgente',
          strategy: 'currentUserThenElevated',
          appPid: 1234,
          assetSize: 5,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          installDirectoryWritable: true,
          requireValidSignature: false,
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          launcherStatusReader: launcherStatusReader,
          automaticFailureBreaker: breaker,
          clock: () => DateTime.utc(2026, 6, 10, 12),
        );

        final resolution = await service.resolvePersistedDownloadedPending();

        expect(resolution, isA<PendingDownloadedStaleCleared>());
        expect(pendingStore.clearCount, 1);
        expect(installer.cleanupCount, 1);
      });
    });

    group('applyPendingDownloadedUpdate', () {
      Future<Result<void>> apply({
        bool triggerAppClose = true,
        String? noticeTitle,
        String? noticeBody,
      }) {
        return service.applyPendingDownloadedUpdate(
          getDiagnostics: () => latestDiagnostics,
          onDiagnosticsUpdated: (diagnostics) => latestDiagnostics = diagnostics,
          persistDiagnostics: () async {
            persistCount++;
          },
          notifyDiagnosticsChanged: () {
            notifyCount++;
          },
          noticeTitle: noticeTitle,
          noticeBody: noticeBody,
          triggerAppClose: triggerAppClose,
        );
      }

      test('uses current process id resolver instead of persisted appPid', () async {
        final pending = PendingSilentUpdateDownloaded(
          version: '99.0.0+1',
          startedAt: DateTime.utc(2026, 6, 10, 12),
          installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
          logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
          launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
          installDirectory: r'C:\PlugAgente',
          strategy: 'currentUserThenElevated',
          appPid: 1,
          assetSize: 5,
          sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
          installDirectoryWritable: true,
          requireValidSignature: false,
          updateDirectorySecurityStatus: 'restricted',
        );
        pendingStore.pending = pending;
        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          automaticFailureBreaker: breaker,
          currentProcessIdResolver: () => 4242,
        );

        await apply(triggerAppClose: false);

        expect(installer.lastLaunchRequest?.appPid, 4242);
      });

      test('launches helper, updates diagnostics and closes app on success', () async {
        pendingStore.pending = _downloadedPending();
        var closeCalled = false;
        String? capturedTitle;
        String? capturedBody;
        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          automaticFailureBreaker: breaker,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCalled = true;
            capturedTitle = noticeTitle;
            capturedBody = noticeBody;
          },
        );

        final result = await apply(
          noticeTitle: 'title',
          noticeBody: 'body',
        );
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        expect(installer.launchHelperCount, 1);
        expect(installer.lastLaunchRequest?.version, '99.0.0+1');
        expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticInstallStarted);
        expect(persistCount, greaterThan(0));
        expect(notifyCount, 1);
        expect(closeCalled, isTrue);
        expect(capturedTitle, 'title');
        expect(capturedBody, 'body');
      });

      test('skips close when triggerAppClose is false', () async {
        pendingStore.pending = _downloadedPending();
        var closeCalled = false;
        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          automaticFailureBreaker: breaker,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCalled = true;
          },
        );

        final result = await apply(triggerAppClose: false);
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        expect(installer.launchHelperCount, 1);
        expect(closeCalled, isFalse);
      });

      test('fails when no pending record exists', () async {
        final result = await apply();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (error) => expect(error, isA<domain.ConfigurationFailure>()),
        );
      });

      test('fails when installer is not configured', () async {
        pendingStore.pending = _downloadedPending();
        service = _makeService(
          pendingStore: pendingStore,
          automaticFailureBreaker: breaker,
        );

        final result = await apply();

        expect(result.isError(), isTrue);
      });

      test('fails when pending record lacks full apply metadata', () async {
        pendingStore.pending = _downloadedPending(fullMetadata: false);

        final result = await apply();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (error) {
            expect(error, isA<domain.ConfigurationFailure>());
            expect(
              (error as domain.Failure).context['reason'],
              'incomplete_pending_record',
            );
          },
        );
        expect(installer.launchHelperCount, 0);
      });

      test('returns launch failure without marking apply in progress', () async {
        pendingStore.pending = _downloadedPending();
        installer.launchResult = Failure(
          domain.ServerFailure.withContext(
            message: 'helper launch failed',
            context: <String, dynamic>{'operation': 'launchPreparedHelper'},
          ),
        );

        final result = await apply();

        expect(result.isError(), isTrue);
        expect(installer.launchHelperCount, 1);
        expect(
          pendingStore.pending,
          isA<PendingSilentUpdateDownloaded>().having(
            (value) => value.launchedAt,
            'launchedAt',
            isNull,
          ),
          reason: 'failed spawn must roll back launchedAt so retry is not blocked',
        );
      });

      test('persists launchedAt before spawn so reconcile treats as in-flight', () async {
        pendingStore.pending = _downloadedPending();
        DateTime? launchedAtSeenDuringSpawn;
        installer.onBeforeLaunchReturn = () async {
          final current = pendingStore.pending;
          launchedAtSeenDuringSpawn =
              current is PendingSilentUpdateDownloaded ? current.launchedAt : null;
        };

        final result = await apply(triggerAppClose: false);

        expect(result.isSuccess(), isTrue);
        expect(launchedAtSeenDuringSpawn, isNotNull);
        expect(
          (pendingStore.pending! as PendingSilentUpdateDownloaded).launchedAt,
          launchedAtSeenDuringSpawn,
        );
      });

      test('apply with recent launchedAt is idempotent Success without second launch', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 11, 55),
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);
        var closeCount = 0;
        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          launcherStatusReader: launcherStatusReader,
          automaticFailureBreaker: breaker,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCount++;
          },
        );

        final result = await apply();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        expect(installer.launchHelperCount, 0);
        expect(closeCount, 1);
      });

      test('apply with concluded/timed-out launch fails without spawning a second helper', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
        );
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);

        final result = await apply(triggerAppClose: false);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (error) {
            expect(error, isA<domain.ConfigurationFailure>());
            expect(
              (error as domain.ConfigurationFailure).context['reason'],
              'launch_concluded_or_timed_out',
            );
          },
        );
        expect(installer.launchHelperCount, 0);
        expect(pendingStore.pending, isNull);
        expect(breaker.failureCount, 1);
        expect(installer.cleanupCount, 1);
      });

      test('apply with terminal helper success is idempotent Success without second launch', () async {
        final pending = _downloadedPending().copyWith(
          launchedAt: DateTime.utc(2026, 6, 10, 10),
        );
        pendingStore.pending = pending;
        await breaker.recordFailure();

        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          launcherStatusReader: _TerminalLauncherStatusReader(
            pending: pending,
            state: 'completed',
            lastUpdatedAt: DateTime.utc(2026, 6, 10, 10),
          ),
          automaticFailureBreaker: breaker,
          clock: () => DateTime.utc(2026, 6, 10, 12),
        );

        final result = await apply(triggerAppClose: false);

        expect(result.isSuccess(), isTrue);
        expect(installer.launchHelperCount, 0);
        expect(pendingStore.pending, isNull);
        expect(breaker.failureCount, 0);
      });

      test('second apply is idempotent: does not relaunch helper but still closes', () async {
        pendingStore.pending = _downloadedPending();
        var closeCount = 0;
        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          automaticFailureBreaker: breaker,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCount++;
          },
        );

        final first = await apply(triggerAppClose: false);
        final second = await apply();
        await Future<void>.delayed(Duration.zero);

        expect(first.isSuccess(), isTrue);
        expect(second.isSuccess(), isTrue);
        expect(installer.launchHelperCount, 1);
        expect(closeCount, 1);
      });

      test('two concurrent calls launch the helper only once (guard is claimed before the await)', () async {
        pendingStore.pending = _downloadedPending();
        final launchGate = Completer<void>();
        installer.onBeforeLaunchReturn = () => launchGate.future;

        // Start both calls back-to-back, before either has a chance to
        // resolve `launchPreparedHelper`. If the guard were claimed only
        // after the await (the pre-fix behavior), both would observe
        // `_applyInProgress == false` and both would call the installer.
        final firstFuture = apply(triggerAppClose: false);
        final secondFuture = apply(triggerAppClose: false);

        // Let both calls run up to the point where they'd read the guard.
        await Future<void>.delayed(Duration.zero);
        expect(installer.launchHelperCount, 1, reason: 'only the first call should have started the launch');

        launchGate.complete();
        final results = await Future.wait([firstFuture, secondFuture]);

        expect(results[0].isSuccess(), isTrue);
        expect(results[1].isSuccess(), isTrue);
        expect(installer.launchHelperCount, 1);
      });

      test('reports and logs when closing the app for install fails, instead of losing the error', () async {
        final pending = _downloadedPending();
        pendingStore.pending = pending;
        launcherStatusReader.existingPaths
          ..add(pending.installerPath)
          ..add(pending.launcherPath);
        service = _makeService(
          installer: installer,
          pendingStore: pendingStore,
          launcherStatusReader: launcherStatusReader,
          automaticFailureBreaker: breaker,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            throw StateError('window manager refused to close');
          },
        );

        final result = await apply();
        // The close failure is reported asynchronously via `.catchError`;
        // give the microtask queue a chance to run it.
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue, reason: 'launching the helper already succeeded');
        expect(latestDiagnostics?.completionSource, UpdateCheckCompletionSource.automaticInstallFailure);
        expect(latestDiagnostics?.errorMessage, contains('window manager refused to close'));
        expect(notifyCount, greaterThanOrEqualTo(2));
        expect(
          pendingStore.pending,
          isA<PendingSilentUpdateDownloaded>().having(
            (value) => value.launchedAt,
            'launchedAt',
            isNotNull,
          ),
        );

        // Close failure resets the in-process guard; launch evidence still
        // makes resolvePersistedDownloadedPending report in-flight.
        final resolution = await service.resolvePersistedDownloadedPending();
        expect(resolution, isA<PendingDownloadedInFlight>());
      });
    });

    group('cleanupArtifacts', () {
      test('invokes installer cleanup on success', () async {
        await service.cleanupArtifacts(installer);

        expect(installer.cleanupCount, 1);
      });

      test('swallows cleanup failures without throwing', () async {
        final failingInstaller = _FailingCleanupInstaller(
          delegate: FakeSilentUpdateInstaller(),
        );

        await expectLater(
          service.cleanupArtifacts(failingInstaller),
          completes,
        );
      });
    });
  });
}

class _InFlightLauncherStatusReader implements ISilentUpdateLauncherStatusReader {
  _InFlightLauncherStatusReader({
    required this.pending,
    required this.lastUpdatedAt,
  });

  final PendingSilentUpdateDownloaded pending;
  final DateTime lastUpdatedAt;

  @override
  Future<bool> fileExists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return path == pending.installerPath || path == pending.launcherPath;
  }

  @override
  Future<SilentUpdateLauncherStatus?> read(String? statusPath) async {
    return SilentUpdateLauncherStatus(
      state: 'started',
      strategy: pending.strategy,
      installDirectory: pending.installDirectory,
      installerPath: pending.installerPath,
      logPath: pending.logPath,
      nonAdminExitCode: null,
      nonAdminDurationMs: null,
      elevatedExitCode: null,
      elevatedDurationMs: null,
      elevatedRetryStarted: null,
      waitForAppExitDurationMs: null,
      appExitTimedOut: null,
      appPid: pending.appPid,
      signatureStatus: null,
      signatureRequired: null,
      actualSha256: null,
      hashValidationStatus: null,
      installDirectoryWritable: true,
      elevatedCancelled: null,
      errorMessage: null,
      lastUpdatedAt: lastUpdatedAt,
    );
  }
}

class _TerminalLauncherStatusReader implements ISilentUpdateLauncherStatusReader {
  _TerminalLauncherStatusReader({
    required this.pending,
    required this.state,
    required this.lastUpdatedAt,
  });

  final PendingSilentUpdateDownloaded pending;
  final String state;
  final DateTime lastUpdatedAt;

  @override
  Future<bool> fileExists(String? path) async {
    if (path == null || path.isEmpty) return false;
    return path == pending.installerPath || path == pending.launcherPath;
  }

  @override
  Future<SilentUpdateLauncherStatus?> read(String? statusPath) async {
    return SilentUpdateLauncherStatus(
      state: state,
      strategy: pending.strategy,
      installDirectory: pending.installDirectory,
      installerPath: pending.installerPath,
      logPath: pending.logPath,
      nonAdminExitCode: null,
      nonAdminDurationMs: null,
      elevatedExitCode: null,
      elevatedDurationMs: null,
      elevatedRetryStarted: null,
      waitForAppExitDurationMs: null,
      appExitTimedOut: null,
      appPid: pending.appPid,
      signatureStatus: null,
      signatureRequired: null,
      actualSha256: null,
      hashValidationStatus: null,
      installDirectoryWritable: true,
      elevatedCancelled: null,
      errorMessage: null,
      lastUpdatedAt: lastUpdatedAt,
    );
  }
}

class _FailingCleanupInstaller implements ISilentUpdateInstaller {
  _FailingCleanupInstaller({required this.delegate});

  final ISilentUpdateInstaller delegate;

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    return Failure(
      domain.ServerFailure.withContext(
        message: 'cleanup failed',
        context: <String, dynamic>{'operation': 'cleanupObsoleteArtifacts'},
      ),
    );
  }

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) => delegate.install(request);

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) =>
      delegate.launchPreparedHelper(request);
}
