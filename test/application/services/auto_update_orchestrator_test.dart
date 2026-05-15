import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

class FakeAutoUpdaterGateway implements IAutoUpdaterGateway {
  UpdaterListener? listener;
  final List<String> feedUrls = <String>[];
  int? interval;
  bool? lastInBackground;
  Exception? checkError;
  Exception? setFeedError;
  Future<void> Function()? onCheckForUpdates;

  @override
  void addListener(UpdaterListener listener) {
    this.listener = listener;
  }

  @override
  Future<void> setFeedURL(String feedUrl) async {
    if (setFeedError != null) {
      throw setFeedError!;
    }
    feedUrls.add(feedUrl);
  }

  @override
  Future<void> checkForUpdates({required bool inBackground}) async {
    lastInBackground = inBackground;
    if (checkError != null) {
      throw checkError!;
    }
    if (onCheckForUpdates != null) {
      await onCheckForUpdates!.call();
    }
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) async {
    this.interval = interval;
  }
}

class FakeAppcastProbeService implements IAppcastProbeService {
  AppcastProbeResult result = const AppcastProbeResult(
    requestUrl: 'https://example.com/appcast.xml',
    latestVersion: '1.0.99+1',
    assetUrl: 'https://example.com/PlugAgente-Setup-1.0.99.exe',
    assetSize: 5,
    assetName: 'PlugAgente-Setup-1.0.99.exe',
    sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
    itemCount: 1,
  );
  String? lastProbeUrl;
  int callCount = 0;

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    callCount++;
    lastProbeUrl = feedUrl;
    return AppcastProbeResult(
      requestUrl: feedUrl,
      latestVersion: result.latestVersion,
      assetUrl: result.assetUrl,
      assetSize: result.assetSize,
      assetName: result.assetName,
      sha256: result.sha256,
      channel: result.channel,
      rolloutPercentage: result.rolloutPercentage,
      itemCount: result.itemCount,
      errorMessage: result.errorMessage,
    );
  }
}

class FakeSilentUpdateInstaller implements ISilentUpdateInstaller {
  SilentUpdateInstallRequest? request;
  Result<SilentUpdateInstallResult> result = const Success(
    SilentUpdateInstallResult(
      installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
      logPath: r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
      launcherPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
      launcherStatusPath: r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
      installDirectory: r'C:\PlugAgente',
      strategy: SilentUpdateInstallStrategy.currentUserThenElevated,
      installDirectoryWritable: true,
      appPid: 1234,
      updateDirectorySecurityStatus: 'restricted',
    ),
  );
  int cleanupCount = 0;

  @override
  Future<Result<SilentUpdateInstallResult>> install(
    SilentUpdateInstallRequest request,
  ) async {
    this.request = request;
    return result;
  }

  @override
  Future<Result<void>> cleanupObsoleteArtifacts() async {
    cleanupCount++;
    return const Success(unit);
  }
}

void main() {
  group('AutoUpdateOrchestrator', () {
    late InMemoryAppSettingsStore settingsStore;
    late MetricsCollector metricsCollector;

    setUp(() {
      dotenv.clean();
      dotenv.loadFromString(
        envString: 'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\nAUTO_UPDATE_CHECK_INTERVAL_SECONDS=3600',
      );
      settingsStore = InMemoryAppSettingsStore();
      metricsCollector = MetricsCollector();
    });

    group('isAvailable', () {
      test('returns false when supportsAutoUpdate is false', () {
        final capabilities = RuntimeCapabilities.degraded(
          reasons: ['Test degradation'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        expect(orchestrator.isAvailable, isFalse);
      });

      test('returns true when supported and feed is configured', () {
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
        );

        expect(orchestrator.isAvailable, isTrue);
      });
    });

    group('initialize', () {
      test('configures feed, interval and listener', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();

        expect(fakeGateway.listener, isNotNull);
        expect(fakeGateway.feedUrls.single, 'https://example.com/appcast.xml');
        expect(fakeGateway.interval, 0);
      });

      test('uses native updater interval when silent updates are disabled', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();

        expect(fakeGateway.interval, 3600);
      });

      test('falls back to official feed when environment is empty', () async {
        dotenv.clean();
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();

        expect(fakeGateway.listener, isNotNull);
        expect(fakeGateway.feedUrls.single, officialAutoUpdateFeedUrl);
        expect(fakeGateway.interval, 0);
      });
    });

    group('checkSilently', () {
      test('is enabled by default', () {
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
        );

        expect(orchestrator.automaticSilentUpdatesEnabled, isTrue);
      });

      test('returns Success(false) when remote version is not newer', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: AppConstants.appVersion,
            assetUrl: 'https://example.com/PlugAgente-Setup-1.6.7.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-1.6.7.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkSilently();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (started) => expect(started, isFalse),
          (_) => fail('Expected success'),
        );
        expect(fakeInstaller.request, isNull);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );
      });

      test('starts installer and persists pending state when remote version is newer', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        var closeCalled = false;
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          closeApplicationForSilentUpdate: () async {
            closeCalled = true;
          },
        );

        final result = await orchestrator.checkSilently();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (started) => expect(started, isTrue),
          (_) => fail('Expected success'),
        );
        expect(fakeInstaller.request?.version, '99.0.0+1');
        expect(fakeInstaller.request?.sha256, '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
        expect(fakeInstaller.request?.requireValidSignature, isFalse);
        expect(closeCalled, isTrue);
        expect(settingsStore.getString('auto_update.pending_silent_update'), contains('99.0.0+1'));
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticInstallStarted,
        );
        expect(
          orchestrator.lastAutomaticDiagnostics?.silentUpdateStrategy,
          SilentUpdateInstallStrategy.currentUserThenElevated.name,
        );
        expect(
          orchestrator.lastAutomaticDiagnostics?.launcherPath,
          r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
        );
        expect(
          orchestrator.lastAutomaticDiagnostics?.launcherStatusPath,
          r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
        );
        expect(orchestrator.lastAutomaticDiagnostics?.appPid, 1234);
        expect(orchestrator.lastAutomaticDiagnostics?.updateDirectorySecurityStatus, 'restricted');
        expect(orchestrator.lastAutomaticDiagnostics?.signatureRequired, isFalse);
      });

      test('reconciles pending update with launcher status on startup', () async {
        final statusDir = Directory.systemTemp.createTempSync('plug_launcher_status_test_');
        addTearDown(() {
          if (statusDir.existsSync()) {
            statusDir.deleteSync(recursive: true);
          }
        });
        final statusFile = File('${statusDir.path}${Platform.pathSeparator}launcher.status.json');
        statusFile.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'state': 'elevatedStarted',
            'strategy': SilentUpdateInstallStrategy.currentUserThenElevated.name,
            'installDirectory': r'C:\PlugAgente',
            'installerPath': r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
            'logPath': r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
            'nonAdminExitCode': 5,
            'nonAdminDurationMs': 1200,
            'elevatedExitCode': 0,
            'elevatedDurationMs': 300,
            'elevatedRetryStarted': true,
            'waitForAppExitDurationMs': 45,
            'appPid': 1234,
            'signatureStatus': 'valid',
            'signatureRequired': true,
            'actualSha256': '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            'hashValidationStatus': 'valid',
            'installDirectoryWritable': true,
            'elevatedCancelled': false,
          }),
        );
        await settingsStore.setString(
          'auto_update.pending_silent_update',
          jsonEncode(<String, Object?>{
            'version': '99.0.0+1',
            'installerPath': r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
            'logPath': r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
            'installDirectory': r'C:\PlugAgente',
            'strategy': SilentUpdateInstallStrategy.currentUserThenElevated.name,
            'launcherPath': r'C:\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
            'launcherStatusPath': statusFile.path,
            'appPid': 1234,
            'updateDirectorySecurityStatus': 'restricted',
          }),
        );
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: AppConstants.appVersion,
            assetUrl: 'https://example.com/PlugAgente-Setup-1.6.7.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-1.6.7.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.startAutomaticChecks();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticPendingFailed,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.nonAdminExitCode, 5);
        expect(orchestrator.lastAutomaticDiagnostics?.nonAdminDurationMs, 1200);
        expect(orchestrator.lastAutomaticDiagnostics?.elevatedExitCode, 0);
        expect(orchestrator.lastAutomaticDiagnostics?.elevatedDurationMs, 300);
        expect(orchestrator.lastAutomaticDiagnostics?.elevatedRetryStarted, isTrue);
        expect(orchestrator.lastAutomaticDiagnostics?.waitForAppExitDurationMs, 45);
        expect(orchestrator.lastAutomaticDiagnostics?.appPid, 1234);
        expect(orchestrator.lastAutomaticDiagnostics?.signatureStatus, 'valid');
        expect(orchestrator.lastAutomaticDiagnostics?.signatureRequired, isTrue);
        expect(orchestrator.lastAutomaticDiagnostics?.actualSha256, startsWith('2cf24'));
        expect(orchestrator.lastAutomaticDiagnostics?.hashValidationStatus, 'valid');
        expect(orchestrator.lastAutomaticDiagnostics?.installDirectoryWritable, isTrue);
        expect(orchestrator.lastAutomaticDiagnostics?.elevatedCancelled, isFalse);
        expect(orchestrator.lastAutomaticDiagnostics?.updateDirectorySecurityStatus, 'restricted');
        expect(
          orchestrator.lastAutomaticDiagnostics?.silentUpdateStrategy,
          SilentUpdateInstallStrategy.currentUserThenElevated.name,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.automaticFailureCount, 1);
        expect(
          orchestrator.lastAutomaticDiagnostics?.errorMessage,
          'Launcher status: elevatedStarted',
        );
        expect(settingsStore.getString('auto_update.pending_silent_update'), isNull);
      });

      test('rejects appcast without SHA-256 before starting installer', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkSilently();

        expect(result.isError(), isTrue);
        expect(fakeInstaller.request, isNull);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticValidationFailure,
        );
      });

      test('skips silent update when appcast channel does not match configured channel', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            channel: 'beta',
            rolloutPercentage: 100,
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkSilently();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (started) => expect(started, isFalse),
          (_) => fail('Expected success'),
        );
        expect(fakeInstaller.request, isNull);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticRolloutSkipped,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.rolloutChannel, 'beta');
        expect(orchestrator.lastAutomaticDiagnostics?.rolloutEligible, isFalse);
      });

      test('skips silent update when rollout bucket is outside percentage', () async {
        await settingsStore.setInt('auto_update.rollout_bucket', 50);
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            channel: 'stable',
            rolloutPercentage: 25,
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkSilently();

        expect(result.isSuccess(), isTrue);
        expect(fakeInstaller.request, isNull);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticRolloutSkipped,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.rolloutBucket, 50);
        expect(orchestrator.lastAutomaticDiagnostics?.rolloutPercentage, 25);
      });

      test('passes signature requirement to silent installer when configured', () async {
        dotenv.clean();
        dotenv.loadFromString(
          envString:
              'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
              'AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=true',
        );
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkSilently();

        expect(result.isSuccess(), isTrue);
        expect(fakeInstaller.request?.requireValidSignature, isTrue);
        expect(orchestrator.lastAutomaticDiagnostics?.signatureRequired, isTrue);
      });

      test('pauses automatic checks after repeated silent update failures', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          automaticFailureCooldownThreshold: 2,
        );

        final first = await orchestrator.checkSilently();
        final second = await orchestrator.checkSilently();
        final probeCallsAfterFailures = fakeProbe.callCount;
        final blocked = await orchestrator.checkSilently();

        expect(first.isError(), isTrue);
        expect(second.isError(), isTrue);
        expect(blocked.isSuccess(), isTrue);
        blocked.fold(
          (started) => expect(started, isFalse),
          (_) => fail('Expected success'),
        );
        expect(fakeProbe.callCount, probeCallsAfterFailures);
        expect(fakeInstaller.request, isNull);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticCooldown,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.automaticFailureCount, 2);
        expect(orchestrator.lastAutomaticDiagnostics?.automaticCooldownUntil, isNotNull);
      });

      test('resets automatic cooldown state when no update is available', () async {
        await settingsStore.setValues(<String, Object>{
          'auto_update.automatic_failure_count': 2,
        });
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: AppConstants.appVersion,
            assetUrl: 'https://example.com/PlugAgente-Setup-1.6.7.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-1.6.7.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkSilently();

        expect(result.isSuccess(), isTrue);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );
        expect(settingsStore.getInt('auto_update.automatic_failure_count'), isNull);
      });

      test('startAutomaticChecks uses silent flow without triggering WinSparkle background UI', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            itemCount: 1,
          );
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.startAutomaticChecks();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(fakeGateway.lastInBackground, isNull);
        expect(fakeInstaller.request?.version, '99.0.0+1');
      });
    });

    group('checkManual', () {
      test('returns Failure when supportsAutoUpdate is false', () async {
        final capabilities = RuntimeCapabilities.degraded(
          reasons: ['Test degradation'],
        );
        final orchestrator = AutoUpdateOrchestrator(capabilities);

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('not supported'));
          },
        );
      });

      test('uses fixed feed and probe cache-busting when update is available', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateAvailable(null);
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (isUpdateAvailable) => expect(isUpdateAvailable, isTrue),
          (_) => fail('Expected success'),
        );
        expect(fakeGateway.lastInBackground, isTrue);
        expect(fakeGateway.feedUrls, <String>['https://example.com/appcast.xml']);
        expect(fakeProbe.lastProbeUrl, contains('cb='));
        expect(orchestrator.lastManualDiagnostics?.configuredFeedUrl, 'https://example.com/appcast.xml');
        expect(orchestrator.lastManualDiagnostics?.requestedFeedUrl, contains('cb='));
        expect(orchestrator.lastManualDiagnostics?.probeRequestUrl, contains('cb='));
        expect(orchestrator.lastManualDiagnostics?.probeSucceeded, isTrue);
        expect(orchestrator.lastManualDiagnostics?.updateAvailable, isTrue);
        expect(
          orchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updateAvailable,
        );
        expect(orchestrator.lastManualDiagnostics?.currentVersion, AppConstants.appVersion);
        expect(metricsCollector.autoUpdateManualCheckStartedCount, 1);
        expect(metricsCollector.autoUpdateManualCheckSuccessAvailableCount, 1);
      });

      test('does not call setFeedURL again after initialize', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateNotAvailable(null);
        };

        await orchestrator.initialize();
        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        expect(fakeGateway.feedUrls, <String>['https://example.com/appcast.xml']);
      });

      test('returns Success(false) when update is not available', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '1.0.13+14',
            itemCount: 4,
          );
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateNotAvailable(null);
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (isUpdateAvailable) => expect(isUpdateAvailable, isFalse),
          (_) => fail('Expected success'),
        );
        expect(fakeGateway.lastInBackground, isTrue);
        expect(orchestrator.lastManualDiagnostics?.updateAvailable, isFalse);
        expect(orchestrator.lastManualDiagnostics?.appcastProbeVersion, '1.0.13+14');
        expect(
          orchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updateNotAvailable,
        );
        expect(metricsCollector.autoUpdateManualCheckSuccessNotAvailableCount, 1);
      });

      test('returns Failure when updater listener does not complete before completion timeout', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          manualCompletionTimeout: const Duration(milliseconds: 10),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('waiting for updater completion'));
          },
        );
        expect(
          orchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.completionTimeout,
        );
        expect(
          orchestrator.lastManualDiagnostics?.errorMessage,
          contains('waiting for updater completion'),
        );
        expect(metricsCollector.autoUpdateManualCheckCompletionTimeoutCount, 1);
      });

      test('returns Failure when trigger does not return before trigger timeout', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService();
        final triggerCompleter = Completer<void>();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          manualTriggerTimeout: const Duration(milliseconds: 10),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        fakeGateway.onCheckForUpdates = () => triggerCompleter.future;

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('trigger timed out'));
          },
        );
        expect(
          orchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.triggerTimeout,
        );
        expect(metricsCollector.autoUpdateManualCheckTriggerTimeoutCount, 1);
      });

      test('returns Failure when check trigger throws', () async {
        final fakeGateway = FakeAutoUpdaterGateway()..checkError = Exception('boom');
        final fakeProbe = FakeAppcastProbeService();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('Failed to trigger update check'));
          },
        );
        expect(
          orchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.triggerFailure,
        );
        expect(
          orchestrator.lastManualDiagnostics?.errorMessage,
          contains('Failed to trigger update check'),
        );
        expect(metricsCollector.autoUpdateManualCheckTriggerFailureCount, 1);
      });

      test('keeps updater trigger running even when probe fails', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml?cb=1',
            errorMessage: 'HTTP 500',
          );
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: fakeProbe,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateNotAvailable(null);
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        expect(orchestrator.lastManualDiagnostics?.probeSucceeded, isFalse);
        expect(orchestrator.lastManualDiagnostics?.probeErrorMessage, 'HTTP 500');
        expect(fakeGateway.lastInBackground, isTrue);
      });
      test('returns Failure with notInitialized completion source when initialize does not finish', () async {
        final fakeGateway = FakeAutoUpdaterGateway()..setFeedError = Exception('init failed');
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.checkManual();

        expect(result.isError(), isTrue);
        expect(
          orchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.notInitialized,
        );
        expect(metricsCollector.autoUpdateManualCheckNotInitializedCount, 1);
      });

      test('persists diagnostics and hydrates them in a new orchestrator instance', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterUpdateNotAvailable(null);
        };

        final result = await orchestrator.checkManual();
        expect(result.isSuccess(), isTrue);

        final restored = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: MetricsCollector(),
        );

        expect(
          restored.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updateNotAvailable,
        );
        expect(
          restored.lastManualDiagnostics?.configuredFeedUrl,
          'https://example.com/appcast.xml',
        );
      });

      test('opens a timeout circuit after repeated timeouts and rejects new checks', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          manualCompletionTimeout: const Duration(milliseconds: 10),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          timeoutCircuitThreshold: 2,
          timeoutCircuitCooldown: const Duration(minutes: 5),
        );

        final firstResult = await orchestrator.checkManual();
        final secondResult = await orchestrator.checkManual();
        final blockedOrchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: FakeAppcastProbeService(),
          manualCompletionTimeout: const Duration(milliseconds: 10),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          timeoutCircuitThreshold: 2,
          timeoutCircuitCooldown: const Duration(minutes: 5),
        );
        final blockedResult = await blockedOrchestrator.checkManual();

        expect(firstResult.isError(), isTrue);
        expect(secondResult.isError(), isTrue);
        expect(blockedResult.isError(), isTrue);
        expect(
          blockedOrchestrator.lastManualDiagnostics?.completionSource,
          UpdateCheckCompletionSource.circuitOpen,
        );
        blockedResult.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as domain.Failure;
            expect(f.message, contains('temporarily paused'));
          },
        );
        expect(metricsCollector.autoUpdateCircuitOpenedCount, 1);
        expect(metricsCollector.autoUpdateCircuitOpenRejectedCount, 1);
      });
    });

    group('checkInBackground', () {
      test('persists background diagnostics and hydrates them in a new orchestrator instance', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();
        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterCheckingForUpdate(null);
          fakeGateway.listener?.onUpdaterUpdateNotAvailable(null);
        };

        await orchestrator.checkInBackground();

        expect(fakeGateway.lastInBackground, isTrue);
        expect(
          orchestrator.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updateNotAvailable,
        );
        expect(orchestrator.lastBackgroundDiagnostics?.updateAvailable, isFalse);
        expect(
          orchestrator.lastBackgroundDiagnostics?.configuredFeedUrl,
          'https://example.com/appcast.xml',
        );

        final restored = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: MetricsCollector(),
        );

        expect(
          restored.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updateNotAvailable,
        );
        expect(restored.lastBackgroundDiagnostics?.updateAvailable, isFalse);
      });

      test('captures trigger failure diagnostics when background check throws', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway()..checkError = Exception('background boom');
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          backgroundRetryLimit: 1,
        );

        await orchestrator.initialize();
        await orchestrator.checkInBackground();

        expect(
          orchestrator.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.triggerFailure,
        );
        expect(
          orchestrator.lastBackgroundDiagnostics?.errorMessage,
          contains('background boom'),
        );
        expect(metricsCollector.autoUpdateBackgroundCheckTriggerFailureCount, 1);
      });

      test('records updater error metric when background listener reports failure', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();
        fakeGateway.onCheckForUpdates = () async {
          fakeGateway.listener?.onUpdaterError(null);
        };

        await orchestrator.checkInBackground();

        expect(
          orchestrator.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updaterError,
        );
        expect(metricsCollector.autoUpdateBackgroundCheckUpdaterErrorCount, 1);
      });
    });
  });
}
