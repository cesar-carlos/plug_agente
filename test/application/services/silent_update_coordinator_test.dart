import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
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

  @override
  Future<Result<SilentUpdateInstallResult>> install(SilentUpdateInstallRequest request) async {
    installCount++;
    this.request = request;
    return result;
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
  Future<void> Function()? closeApp,
}) {
  final settings = store ?? InMemoryAppSettingsStore();
  dotenv.clean();
  dotenv.loadFromString(
    envString: 'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
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
  );
}

void main() {
  setUpAll(() {
    dotenv.clean();
    dotenv.loadFromString(
      envString: 'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
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
        result.fold((v) => expect(v, isFalse), (_) => fail('Expected success'));
        expect(installer.installCount, 0);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticDisabled,
        );
      });

      test('calls installer and closes app when newer version is found', () async {
        final installer = _FakeInstaller();
        var closeCalled = false;
        final coordinator = _makeCoordinator(
          installer: installer,
          closeApp: () async {
            closeCalled = true;
          },
        );

        final result = await coordinator.checkSilently();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        result.fold((v) => expect(v, isTrue), (_) => fail('Expected success'));
        expect(installer.installCount, 1);
        expect(closeCalled, isTrue);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticInstallStarted,
        );
      });

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
        thirdResult.fold((v) => expect(v, isFalse), (_) => fail('Expected success'));
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
        final installer = _FakeInstaller()
          ..installCount = 0;

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
          closeApplicationForSilentUpdate: () async {
            closeCalled = true;
          },
        );

        final result = await coordinator.checkSilently();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        result.fold((v) => expect(v, isFalse), (_) => fail('Expected success'));
        expect(closeCalled, isFalse);
        expect(
          coordinator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticDisabled,
        );
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

    group('reconcilePendingAndSchedule', () {
      test('clears stale pending record without incrementing failure count', () async {
        final store = InMemoryAppSettingsStore();
        final stalePending = <String, Object?>{
          'version': '99.0.0+1',
          'installerPath': r'C:\OldPath\App\updates\PlugAgente-Setup-99.0.0.exe',
          'launcherPath': r'C:\OldPath\App\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          'launcherStatusPath':
              r'C:\OldPath\App\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
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
  Future<Result<void>> cleanupObsoleteArtifacts() => delegate.cleanupObsoleteArtifacts();
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
