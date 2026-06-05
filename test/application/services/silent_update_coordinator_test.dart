import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/runtime/i_uac_detector.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

// Minimal fakes reused from orchestrator tests.
class _FakeProbe implements IAppcastProbeService {
  AppcastProbeResult result = const AppcastProbeResult(
    requestUrl: 'https://example.com/appcast.xml',
    latestVersion: '99.0.0+1',
    assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
    assetSize: 5,
    assetName: 'PlugAgente-Setup-99.0.0.exe',
    sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    itemCount: 1,
  );
  int callCount = 0;

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    callCount++;
    return AppcastProbeResult(
      requestUrl: feedUrl,
      latestVersion: result.latestVersion,
      assetUrl: result.assetUrl,
      assetSize: result.assetSize,
      assetName: result.assetName,
      sha256: result.sha256,
      os: result.os,
      channel: result.channel,
      rolloutPercentage: result.rolloutPercentage,
      itemCount: result.itemCount,
      errorMessage: result.errorMessage,
    );
  }
}

class _FakeInstaller implements ISilentUpdateInstaller {
  SilentUpdateInstallRequest? request;
  Result<SilentUpdateInstallResult> result = const Success(
    SilentUpdateInstallResult(
      installerPath: r'C:\App\updates\PlugAgente-Setup-99.0.0.exe',
      logPath: r'C:\App\updates\PlugAgente-Update-99.0.0+1.log',
      launcherPath: r'C:\App\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
      launcherStatusPath: r'C:\App\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
      installDirectory: r'C:\App',
      strategy: SilentUpdateInstallStrategy.currentUserThenElevated,
      installDirectoryWritable: true,
      appPid: 9876,
      updateDirectorySecurityStatus: 'restricted',
    ),
  );
  int installCount = 0;
  int cleanupCount = 0;
  int launchHelperCount = 0;
  SilentUpdateLaunchRequest? lastLaunchRequest;
  Result<void> launchResult = const Success(unit);

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    installCount++;
    this.request = request;
    return result;
  }

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) async {
    launchHelperCount++;
    lastLaunchRequest = request;
    return launchResult;
  }

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    cleanupCount++;
    return const Success(unit);
  }
}

SilentUpdateCoordinator _makeCoordinator({
  InMemoryAppSettingsStore? store,
  _FakeProbe? probe,
  _FakeInstaller? installer,
  CloseApplicationForSilentUpdate? closeApp,
  IUacDetector? uacDetector,
}) {
  final settings = store ?? InMemoryAppSettingsStore();
  dotenv.clean();
  dotenv.loadFromString(
    envString:
        'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
        'AUTO_UPDATE_CHECK_INTERVAL_SECONDS=3600',
  );
  return SilentUpdateCoordinator(
    RuntimeCapabilities.full(),
    () {
      const url = 'https://example.com/appcast.xml';
      return url;
    },
    appcastProbeService: probe ?? _FakeProbe(),
    silentUpdateInstaller: installer ?? _FakeInstaller(),
    settingsStore: settings,
    closeApplicationForSilentUpdate: closeApp,
    uacDetector: uacDetector,
  );
}

class _StubUacDetector implements IUacDetector {
  _StubUacDetector({required this.requiresConsent});

  final bool requiresConsent;
  int callCount = 0;

  @override
  bool requiresUserConsentForElevation() {
    callCount++;
    return requiresConsent;
  }

  @override
  UacDetectionState detect() {
    return UacDetectionState(
      elevationType: requiresConsent ? UacElevationType.limited : UacElevationType.full,
      uacEnabled: requiresConsent,
      requiresConsent: requiresConsent,
    );
  }
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

  group('SilentUpdateCoordinator', () {
    group('checkSilently', () {
      test('returns false without calling installer when silent updates are disabled', () async {
        final store = InMemoryAppSettingsStore();
        await store.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final installer = _FakeInstaller();
        final coordinator = _makeCoordinator(store: store, installer: installer);

        final result = await coordinator.checkSilently();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.silentDisabled),
          (_) => fail('Expected success'),
        );
        expect(installer.installCount, 0);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticDisabled,
        );
      });

      test(
        'stages installer without closing app when newer version is found',
        () async {
          final installer = _FakeInstaller();
          var closeCalled = false;
          final coordinator = _makeCoordinator(
            installer: installer,
            closeApp: ({String? noticeTitle, String? noticeBody}) async {
              closeCalled = true;
            },
          );

          final result = await coordinator.checkSilently();
          await Future<void>.delayed(Duration.zero);

          expect(result.isSuccess(), isTrue);
          result.fold(
            (outcome) {
              expect(outcome, SilentUpdateOutcome.installerReady);
              expect(outcome.isInstallerReady, isTrue);
            },
            (_) => fail('Expected success'),
          );
          expect(installer.installCount, 1);
          expect(
            installer.request?.deferHelperLaunch,
            isTrue,
            reason: 'silent path must stage the helper without launching it',
          );
          expect(
            installer.launchHelperCount,
            0,
            reason: 'helper launch must wait for an explicit apply',
          );
          expect(
            closeCalled,
            isFalse,
            reason: 'agent must stay online: closeApplication is only called from the apply step',
          );
          expect(
            coordinator.lastAutomaticDiagnostics?.completionSource,
            UpdateCheckCompletionSource.automaticInstallReady,
          );
        },
      );

      test(
        'applyPendingDownloadedUpdate launches helper and invokes close',
        () async {
          final installer = _FakeInstaller();
          var closeCalled = false;
          String? capturedTitle;
          String? capturedBody;
          final coordinator = _makeCoordinator(
            installer: installer,
            closeApp: ({String? noticeTitle, String? noticeBody}) async {
              closeCalled = true;
              capturedTitle = noticeTitle;
              capturedBody = noticeBody;
            },
          );

          final downloadResult = await coordinator.checkSilently();
          expect(downloadResult.isSuccess(), isTrue);
          expect(
            await coordinator.hasPendingDownloadedUpdate,
            isFalse,
            reason: 'pending paths point to a non-existent test directory',
          );

          // Force a pending record with paths recognized as existing by the
          // coordinator's file checks would require a temp directory; here
          // we only validate the orchestration path through the launch and
          // close callbacks using the fake installer.
          final applyResult = await coordinator.applyPendingDownloadedUpdate(
            noticeTitle: 'localized title',
            noticeBody: 'localized body',
          );
          await Future<void>.delayed(Duration.zero);

          expect(applyResult.isSuccess(), isTrue);
          expect(installer.launchHelperCount, 1);
          expect(installer.lastLaunchRequest?.version, '99.0.0+1');
          expect(closeCalled, isTrue);
          expect(capturedTitle, 'localized title');
          expect(capturedBody, 'localized body');
        },
      );

      test(
        'applyPendingDownloadedUpdate with triggerAppClose=false skips close',
        () async {
          final installer = _FakeInstaller();
          var closeCalled = false;
          final coordinator = _makeCoordinator(
            installer: installer,
            closeApp: ({String? noticeTitle, String? noticeBody}) async {
              closeCalled = true;
            },
          );

          await coordinator.checkSilently();
          final applyResult = await coordinator.applyPendingDownloadedUpdate(
            triggerAppClose: false,
          );
          await Future<void>.delayed(Duration.zero);

          expect(applyResult.isSuccess(), isTrue);
          expect(installer.launchHelperCount, 1);
          expect(
            closeCalled,
            isFalse,
            reason: 'shutdown path must launch the helper without re-entering the close callback',
          );
        },
      );

      test('applyPendingDownloadedUpdate fails when no pending record', () async {
        final coordinator = _makeCoordinator();

        final result = await coordinator.applyPendingDownloadedUpdate();

        expect(result.isError(), isTrue);
      });

      test(
        'applyPendingDownloadedUpdate is idempotent: a second call does not relaunch the helper',
        () async {
          final installer = _FakeInstaller();
          var closeCount = 0;
          final coordinator = _makeCoordinator(
            installer: installer,
            closeApp: ({String? noticeTitle, String? noticeBody}) async {
              closeCount++;
            },
          );

          await coordinator.checkSilently();

          final first = await coordinator.applyPendingDownloadedUpdate(triggerAppClose: false);
          // Mirrors the race where the shutdown path already launched the
          // helper and the operator's "Install now" click arrives afterwards.
          final second = await coordinator.applyPendingDownloadedUpdate();
          await Future<void>.delayed(Duration.zero);

          expect(first.isSuccess(), isTrue);
          expect(second.isSuccess(), isTrue);
          expect(
            installer.launchHelperCount,
            1,
            reason: 'the native helper holds a global mutex; a second launch would only clobber its status file',
          );
          expect(
            closeCount,
            1,
            reason: 'the no-op second call must still honour triggerAppClose so the UI close path is not lost',
          );
        },
      );

      test('returns false when probe reports no newer version', () async {
        final probe = _FakeProbe()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '0.0.1+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-0.0.1.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-0.0.1.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final installer = _FakeInstaller();
        final coordinator = _makeCoordinator(probe: probe, installer: installer);

        final result = await coordinator.checkSilently();

        expect(result.isSuccess(), isTrue);
        expect(installer.installCount, 0);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );
      });

      test('records probe error and increments failure count', () async {
        final probe = _FakeProbe()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            errorMessage: 'HTTP 503',
          );
        final coordinator = _makeCoordinator(probe: probe);

        final result = await coordinator.checkSilently();

        expect(result.isError(), isTrue);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticDownloadFailure,
        );
        expect(coordinator.lastAutomaticDiagnostics?.automaticFailureCount, 1);
      });

      test('pauses after reaching failure cooldown threshold', () async {
        final probe = _FakeProbe()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            errorMessage: 'network error',
          );
        final store = InMemoryAppSettingsStore();
        final coordinator = SilentUpdateCoordinator(
          RuntimeCapabilities.full(),
          () => 'https://example.com/appcast.xml',
          appcastProbeService: probe,
          silentUpdateInstaller: _FakeInstaller(),
          settingsStore: store,
          automaticFailureCooldownThreshold: 2,
          automaticFailureCooldown: const Duration(hours: 1),
        );

        await coordinator.checkSilently();
        await coordinator.checkSilently();
        final thirdResult = await coordinator.checkSilently();

        expect(thirdResult.isSuccess(), isTrue);
        thirdResult.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.cooldownActive),
          (_) => fail('Expected success'),
        );
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticCooldown,
        );
      });

      test('rollout bucket is consistent within a single check', () async {
        final store = InMemoryAppSettingsStore();
        final probe = _FakeProbe()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            channel: 'stable',
            rolloutPercentage: 100,
            itemCount: 1,
          );
        final coordinator = _makeCoordinator(store: store, probe: probe);

        await coordinator.checkSilently();

        final persistedBucket = store.getInt('auto_update.rollout_bucket');
        expect(coordinator.lastAutomaticDiagnostics?.rolloutBucket, persistedBucket);
      });

      test('does not close app when silent updates are disabled mid-download', () async {
        final store = InMemoryAppSettingsStore();
        var closeCalled = false;
        late SilentUpdateCoordinator coordinator;
        final installer = _FakeInstaller()..installCount = 0;

        // Coordinator reference needed inside onBeforeReturn — build it before using it.
        coordinator = SilentUpdateCoordinator(
          RuntimeCapabilities.full(),
          () => 'https://example.com/appcast.xml',
          appcastProbeService: _FakeProbe(),
          silentUpdateInstaller: _InstallerWithHook(
            delegate: installer,
            beforeReturn: () async {
              await store.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
            },
          ),
          settingsStore: store,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCalled = true;
          },
        );

        final result = await coordinator.checkSilently();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.silentDisabled),
          (_) => fail('Expected success'),
        );
        expect(closeCalled, isFalse);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticDisabled,
        );
      });

      test('blocks automatic download when UAC detector requires user consent', () async {
        final installer = _FakeInstaller();
        final uacDetector = _StubUacDetector(requiresConsent: true);
        final coordinator = _makeCoordinator(
          installer: installer,
          uacDetector: uacDetector,
        );

        final result = await coordinator.checkSilently();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.requiresUserConsent),
          (_) => fail('Expected success'),
        );
        expect(installer.installCount, 0, reason: 'UAC gate must stop before downloading');
        expect(uacDetector.callCount, greaterThanOrEqualTo(1));
        final diagnostics = coordinator.lastAutomaticDiagnostics;
        expect(
          diagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        );
        expect(diagnostics?.updateAvailable, isTrue);
        expect(diagnostics?.pendingVersion, '99.0.0+1');
      });

      test('userInitiated bypasses UAC gate and runs full download', () async {
        final installer = _FakeInstaller();
        final uacDetector = _StubUacDetector(requiresConsent: true);
        final coordinator = _makeCoordinator(
          installer: installer,
          uacDetector: uacDetector,
        );

        final result = await coordinator.checkSilently(userInitiated: true);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.installerReady),
          (_) => fail('Expected success'),
        );
        expect(installer.installCount, 1, reason: 'user-initiated path must bypass UAC gate');
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticInstallReady,
        );
      });

      test('automatic download proceeds when UAC detector reports no consent needed', () async {
        final installer = _FakeInstaller();
        final uacDetector = _StubUacDetector(requiresConsent: false);
        final coordinator = _makeCoordinator(
          installer: installer,
          uacDetector: uacDetector,
        );

        final result = await coordinator.checkSilently();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.installerReady),
          (_) => fail('Expected success'),
        );
        expect(installer.installCount, 1);
      });

      test('isSilentCheckInProgress is true during check and false after', () async {
        final probe = _FakeProbe();
        var wasInProgressDuringProbe = false;
        final capturingProbe = _CapturingProbe(
          delegate: probe,
          onProbe: (coord) {
            wasInProgressDuringProbe = coord.isSilentCheckInProgress;
          },
        );
        late SilentUpdateCoordinator coordinator;
        coordinator = SilentUpdateCoordinator(
          RuntimeCapabilities.full(),
          () => 'https://example.com/appcast.xml',
          appcastProbeService: capturingProbe..setCoordinator(() => coordinator),
          silentUpdateInstaller: _FakeInstaller(),
          settingsStore: InMemoryAppSettingsStore(),
        );

        expect(coordinator.isSilentCheckInProgress, isFalse);
        await coordinator.checkSilently();
        expect(coordinator.isSilentCheckInProgress, isFalse);
        expect(wasInProgressDuringProbe, isTrue);
      });
    });

    group('cancellation', () {
      test('requestCancellation while download is in flight surfaces cancelled outcome', () async {
        final store = InMemoryAppSettingsStore();
        final cancellableInstaller = _CancellableInstaller();
        late SilentUpdateCoordinator coordinator;
        var closeCalled = false;
        coordinator = SilentUpdateCoordinator(
          RuntimeCapabilities.full(),
          () => 'https://example.com/appcast.xml',
          appcastProbeService: _FakeProbe(),
          silentUpdateInstaller: cancellableInstaller,
          settingsStore: store,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCalled = true;
          },
        );

        final checkFuture = coordinator.checkSilently();
        await cancellableInstaller.entered.future;
        coordinator.requestCancellation();
        cancellableInstaller.release();

        final result = await checkFuture;

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.cancelled),
          (_) => fail('Expected success'),
        );
        expect(closeCalled, isFalse, reason: 'cancelled flow must not close the app');
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticCancelled,
        );
        expect(
          store.getString('auto_update.pending_silent_update'),
          isNull,
          reason: 'cancellation must clear pending so the next check can run',
        );
        expect(
          store.getInt('auto_update.automatic_failure_count'),
          isNull,
          reason: 'cancellation is user-driven and must not feed the cooldown',
        );
      });

      test('requestCancellation is a no-op when no check is in progress', () async {
        final coordinator = _makeCoordinator();
        coordinator.requestCancellation();
        final result = await coordinator.checkSilently();
        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, isNot(SilentUpdateOutcome.cancelled)),
          (_) => fail('Expected success'),
        );
      });
    });

    group('reconcilePendingAndSchedule', () {
      test('clears stale pending record without incrementing failure count', () async {
        final store = InMemoryAppSettingsStore();
        final stalePending = <String, Object?>{
          'version': '99.0.0+1',
          'installerPath': r'C:\OldPath\App\updates\PlugAgente-Setup-99.0.0.exe',
          'launcherPath': r'C:\OldPath\App\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          'launcherStatusPath': r'C:\OldPath\App\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
          'logPath': r'C:\OldPath\App\updates\PlugAgente-Update-99.0.0+1.log',
          'installDirectory': r'C:\OldPath\App',
          'strategy': 'currentUserThenElevated',
          'appPid': 9999,
          'updateDirectorySecurityStatus': 'restricted',
          'startedAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        };
        await store.setString(
          'auto_update.pending_silent_update',
          jsonEncode(stalePending),
        );

        final coordinator = _makeCoordinator(store: store);
        await coordinator.reconcilePendingAndSchedule();

        expect(store.getInt('auto_update.automatic_failure_count'), isNull);
        expect(store.getString('auto_update.pending_silent_update'), isNull);
      });

      test('clears stale pending with null paths from a pre-download crash', () async {
        // Reproduces the window where the coordinator persisted the pending
        // record (before install) and the process crashed before paths were
        // populated. Next boot must clear it instead of blocking checks
        // forever.
        final store = InMemoryAppSettingsStore();
        final stalePending = <String, Object?>{
          'version': '99.0.0+1',
          'installerPath': null,
          'launcherPath': null,
          'launcherStatusPath': null,
          'logPath': null,
          'installDirectory': null,
          'strategy': null,
          'appPid': null,
          'updateDirectorySecurityStatus': null,
          'startedAt': DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
        };
        await store.setString(
          'auto_update.pending_silent_update',
          jsonEncode(stalePending),
        );

        final coordinator = _makeCoordinator(store: store);
        await coordinator.reconcilePendingAndSchedule();

        expect(
          store.getString('auto_update.pending_silent_update'),
          isNull,
          reason: 'pending record without paths must be considered stale and cleared',
        );
        expect(
          store.getInt('auto_update.automatic_failure_count'),
          isNull,
          reason: 'pre-download crash recovery must not increment failure counter',
        );
      });
    });

    group('scheduleAndStart boot jitter', () {
      // Drive these tests with FakeAsync so we exercise the timer logic
      // deterministically without sleeping real wall-clock seconds; the
      // legacy version pumped microtasks repeatedly which was flaky on
      // slow CI runners.
      test('bootJitterProvider defers the immediate boot check', () {
        FakeAsync().run((async) {
          final probe = _FakeProbe();
          final coordinator = SilentUpdateCoordinator(
            RuntimeCapabilities.full(),
            () => 'https://example.com/appcast.xml',
            appcastProbeService: probe,
            silentUpdateInstaller: _FakeInstaller(),
            settingsStore: InMemoryAppSettingsStore(),
            bootJitterProvider: () => const Duration(seconds: 30),
          );

          coordinator.scheduleAndStart();

          // Before the jitter elapses the probe must remain untouched.
          async.elapse(const Duration(seconds: 29));
          expect(probe.callCount, 0);

          // Once the jitter elapses the immediate check fires.
          async.elapse(const Duration(seconds: 2));
          expect(probe.callCount, 1);
          coordinator.stop();
        });
      });

      test('null jitter provider preserves immediate boot check (backward compat)', () {
        FakeAsync().run((async) {
          final probe = _FakeProbe();
          final coordinator = SilentUpdateCoordinator(
            RuntimeCapabilities.full(),
            () => 'https://example.com/appcast.xml',
            appcastProbeService: probe,
            silentUpdateInstaller: _FakeInstaller(),
            settingsStore: InMemoryAppSettingsStore(),
          );

          coordinator.scheduleAndStart();
          async.flushMicrotasks();
          // Allow the very first microtask-driven probe to flush.
          async.elapse(const Duration(milliseconds: 1));

          expect(probe.callCount, 1);
          coordinator.stop();
        });
      });

      test('zero jitter behaves like no jitter (runs immediately)', () {
        FakeAsync().run((async) {
          final probe = _FakeProbe();
          final coordinator = SilentUpdateCoordinator(
            RuntimeCapabilities.full(),
            () => 'https://example.com/appcast.xml',
            appcastProbeService: probe,
            silentUpdateInstaller: _FakeInstaller(),
            settingsStore: InMemoryAppSettingsStore(),
            bootJitterProvider: () => Duration.zero,
          );

          coordinator.scheduleAndStart();
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 1));

          expect(probe.callCount, 1);
          coordinator.stop();
        });
      });
    });

    group('stop / scheduleAndStart', () {
      test('stop cancels the periodic timer (no further checks after stop)', () async {
        final probe = _FakeProbe();
        final coordinator = _makeCoordinator(probe: probe);

        coordinator.scheduleAndStart();
        await Future<void>.delayed(Duration.zero);
        final countAfterStart = probe.callCount;

        coordinator.stop();
        await Future<void>.delayed(Duration.zero);
        expect(probe.callCount, countAfterStart);
      });
    });

    group('clearPersistedAutomaticDiagnostics', () {
      test('clears in-memory and persisted automatic diagnostics', () async {
        final store = InMemoryAppSettingsStore();
        final coordinator = _makeCoordinator(store: store);
        final diagnostics = UpdateCheckDiagnostics(
          checkedAt: DateTime(2026, 5, 14, 11, 20),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          currentVersion: '1.6.7+1',
          completedAt: DateTime(2026, 5, 14, 11, 21),
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
        );
        await store.setString(
          'auto_update.last_automatic_diagnostics',
          jsonEncode(diagnostics.toJson()),
        );
        coordinator.hydratePersistedDiagnostics();
        expect(coordinator.lastAutomaticDiagnostics, isNotNull);

        await coordinator.clearPersistedAutomaticDiagnostics();

        expect(coordinator.lastAutomaticDiagnostics, isNull);
        expect(store.getString('auto_update.last_automatic_diagnostics'), isNull);
      });
    });
  });
}

// Helper: installer that runs a hook before returning the result.
class _InstallerWithHook implements ISilentUpdateInstaller {
  const _InstallerWithHook({required this.delegate, required this.beforeReturn});
  final ISilentUpdateInstaller delegate;
  final Future<void> Function() beforeReturn;

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    await beforeReturn();
    return delegate.install(request);
  }

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) =>
      delegate.launchPreparedHelper(request);

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() => delegate.cleanupObsoleteArtifacts();
}

// Helper: installer that suspends inside install() until released, allowing
// the test to call coordinator.requestCancellation() mid-flight and observe
// the cancellation contract.
class _CancellableInstaller implements ISilentUpdateInstaller {
  final Completer<void> entered = Completer<void>();
  final Completer<void> _release = Completer<void>();
  SilentUpdateInstallRequest? lastRequest;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    lastRequest = request;
    if (!entered.isCompleted) entered.complete();
    await _release.future;
    if (request.cancelRequested?.call() ?? false) {
      return Failure<SilentUpdateInstallResult, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Silent update cancelled before completion',
          context: <String, dynamic>{
            'operation': 'silentUpdateInstall',
            SilentUpdateInstallRequest.cancellationContextKey: true,
            'version': request.version,
          },
        ),
      );
    }
    return const Success(
      SilentUpdateInstallResult(
        installerPath: r'C:\App\updates\PlugAgente-Setup-99.0.0.exe',
        logPath: r'C:\App\updates\PlugAgente-Update-99.0.0+1.log',
        launcherPath: r'C:\App\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
        launcherStatusPath: r'C:\App\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
        installDirectory: r'C:\App',
        strategy: SilentUpdateInstallStrategy.currentUserThenElevated,
        installDirectoryWritable: true,
        appPid: 9876,
        updateDirectorySecurityStatus: 'restricted',
      ),
    );
  }

  @override
  Future<Result<void>> launchPreparedHelper(SilentUpdateLaunchRequest request) async => const Success(unit);

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async => const Success(unit);
}

// Helper: probe that captures whether coordinator.isSilentCheckInProgress during probe.
class _CapturingProbe implements IAppcastProbeService {
  _CapturingProbe({required this.delegate, required this.onProbe});
  final IAppcastProbeService delegate;
  final void Function(SilentUpdateCoordinator) onProbe;
  SilentUpdateCoordinator Function()? _getCoordinator;

  void setCoordinator(SilentUpdateCoordinator Function() getter) {
    _getCoordinator = getter;
  }

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final coord = _getCoordinator?.call();
    if (coord != null) onProbe(coord);
    return delegate.probeLatest(feedUrl: feedUrl, timeout: timeout);
  }
}
