import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_installer.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/application/services/updater_event.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:plug_agente/infrastructure/services/file_silent_update_launcher_status_reader.dart';
import 'package:result_dart/result_dart.dart';

class FakeAutoUpdaterGateway implements IAutoUpdaterGateway {
  UpdaterListener? listener;
  final List<String> feedUrls = <String>[];
  int? interval;
  bool? lastInBackground;
  Exception? checkError;
  Exception? setFeedError;
  Future<void> Function()? onCheckForUpdates;
  final StreamController<UpdaterEvent> _eventsController = StreamController<UpdaterEvent>.broadcast();

  @override
  Stream<UpdaterEvent> get events => _eventsController.stream;

  /// Emits [event] and yields control to the event loop so the
  /// orchestrator's subscription has a chance to handle it before the
  /// test continues with assertions. Replaces the legacy
  /// `listener?.onUpdaterX(...)` calls now that the orchestrator
  /// consumes the sealed stream instead of mixing `UpdaterListener`.
  Future<void> emit(UpdaterEvent event) async {
    _eventsController.add(event);
    await Future<void>.delayed(Duration.zero);
  }

  /// Mirrors `StreamController.hasListener`. Lets tests assert that the
  /// orchestrator subscribed to [events] (the new contract) without
  /// reaching for the legacy `addListener` plumbing.
  bool get hasEventSubscribers => _eventsController.hasListener;

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
      os: result.os,
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
  int installCount = 0;
  int launchHelperCount = 0;
  SilentUpdateLaunchRequest? lastLaunchRequest;
  Result<void> launchResult = const Success(unit);

  /// Optional hook executed just before the install result is returned, allowing
  /// tests to simulate state changes that happen during download (e.g. the user
  /// disabling silent updates while the installer is running).
  Future<void> Function()? onBeforeReturn;

  @override
  Future<Result<SilentUpdateInstallResult>> install(
    SilentUpdateInstallRequest request,
  ) async {
    installCount++;
    this.request = request;
    if (onBeforeReturn != null) {
      await onBeforeReturn!();
    }
    return result;
  }

  @override
  Future<Result<void>> launchPreparedHelper(
    SilentUpdateLaunchRequest request,
  ) async {
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

class FakeSilentUpdateCoordinator implements ISilentUpdateCoordinator {
  bool _isSilentCheckInProgress = false;
  bool automaticSilentUpdatesEnabledValue = true;
  bool hasPendingDownloadedUpdateValue = false;
  UpdateCheckDiagnostics? lastAutomaticDiagnosticsValue;

  int reconcilePendingAndScheduleCallCount = 0;
  int scheduleAndStartCallCount = 0;
  int stopCallCount = 0;
  int checkSilentlyCallCount = 0;
  int applyPendingCallCount = 0;
  bool? lastApplyTriggerAppClose;
  String? lastApplyNoticeTitle;
  String? lastApplyNoticeBody;
  int hydrateCallCount = 0;

  Result<SilentUpdateOutcome> checkSilentlyResult = const Success(SilentUpdateOutcome.noNewVersion);
  Result<void> applyPendingResult = const Success(unit);

  void setInProgress(bool value) => _isSilentCheckInProgress = value;

  @override
  bool get isSilentCheckInProgress => _isSilentCheckInProgress;

  @override
  bool get automaticSilentUpdatesEnabled => automaticSilentUpdatesEnabledValue;

  @override
  Future<bool> get hasPendingDownloadedUpdate async => hasPendingDownloadedUpdateValue;

  @override
  UpdateCheckDiagnostics? get lastAutomaticDiagnostics => lastAutomaticDiagnosticsValue;

  @override
  void hydratePersistedDiagnostics() => hydrateCallCount++;

  @override
  Future<void> reconcilePendingAndSchedule() async => reconcilePendingAndScheduleCallCount++;

  bool? lastCheckSilentlyUserInitiated;

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently({bool userInitiated = false}) async {
    checkSilentlyCallCount++;
    lastCheckSilentlyUserInitiated = userInitiated;
    return checkSilentlyResult;
  }

  @override
  Future<Result<void>> applyPendingDownloadedUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    applyPendingCallCount++;
    lastApplyNoticeTitle = noticeTitle;
    lastApplyNoticeBody = noticeBody;
    lastApplyTriggerAppClose = triggerAppClose;
    return applyPendingResult;
  }

  bool? lastScheduleAndStartRunImmediately;

  @override
  void scheduleAndStart({bool runImmediately = true}) {
    scheduleAndStartCallCount++;
    lastScheduleAndStartRunImmediately = runImmediately;
  }

  @override
  void stop() => stopCallCount++;

  @override
  void requestCancellation() => requestCancellationCallCount++;

  int requestCancellationCallCount = 0;
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
      test('configures feed, interval and event subscription', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();

        expect(
          fakeGateway.hasEventSubscribers,
          isTrue,
          reason: 'orchestrator must subscribe to the gateway events stream',
        );
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

        expect(fakeGateway.hasEventSubscribers, isTrue);
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

      test('returns SilentUpdateOutcome.noNewVersion when remote version is not newer', () async {
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
          (outcome) => expect(outcome, SilentUpdateOutcome.noNewVersion),
          (_) => fail('Expected success'),
        );
        expect(fakeInstaller.request, isNull);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );
      });

      test('stages installer and persists pending state when remote version is newer', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            os: 'windows',
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
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCalled = true;
          },
        );

        final result = await orchestrator.checkSilently();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) {
            expect(outcome, SilentUpdateOutcome.installerReady);
            expect(outcome.isInstallerReady, isTrue);
          },
          (_) => fail('Expected success'),
        );
        expect(fakeInstaller.request?.version, '99.0.0+1');
        expect(fakeInstaller.request?.sha256, '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
        expect(fakeInstaller.request?.requireValidSignature, isTrue);
        expect(
          fakeInstaller.request?.deferHelperLaunch,
          isTrue,
          reason: 'silent path must stage the helper without launching it',
        );
        expect(
          fakeInstaller.launchHelperCount,
          0,
          reason: 'helper launch is reserved for the explicit apply step',
        );
        expect(
          closeCalled,
          isFalse,
          reason: 'agent must stay online after a successful silent download',
        );
        expect(settingsStore.getString('auto_update.pending_silent_update'), contains('99.0.0+1'));
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticInstallReady,
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
        expect(orchestrator.lastAutomaticDiagnostics?.signatureRequired, isTrue);
        expect(orchestrator.lastAutomaticDiagnostics?.appcastProbeOs, 'windows');
      });

      test('does not close the app when silent updates are disabled mid-download', () async {
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
        // Installer that disables silent updates after returning success,
        // simulating the user toggling the setting while the download ran.
        var closeCalled = false;
        late AutoUpdateOrchestrator orchestrator;
        final fakeInstaller = FakeSilentUpdateInstaller()
          ..onBeforeReturn = () async {
            await orchestrator.setAutomaticSilentUpdatesEnabled(false);
          };
        orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          closeApplicationForSilentUpdate: ({String? noticeTitle, String? noticeBody}) async {
            closeCalled = true;
          },
        );

        final result = await orchestrator.checkSilently();
        await Future<void>.delayed(Duration.zero);

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.cancelled),
          (_) => fail('Expected success'),
        );
        expect(closeCalled, isFalse);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticCancelled,
        );
        // Pending install record should have been cleared.
        expect(settingsStore.getString('auto_update.pending_silent_update'), isNull);
      });

      test('runs only one probe and install for concurrent silent checks', () async {
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

        final firstFuture = orchestrator.checkSilently();
        final secondFuture = orchestrator.checkSilently();
        final results = await Future.wait(<Future<Result<SilentUpdateOutcome>>>[
          firstFuture,
          secondFuture,
        ]);

        expect(fakeProbe.callCount, 1);
        expect(fakeInstaller.installCount, 1);
        final outcomes = <SilentUpdateOutcome>[];
        for (final result in results) {
          result.fold(
            outcomes.add,
            (_) => fail('Expected success'),
          );
        }
        expect(outcomes.where((o) => o == SilentUpdateOutcome.installerReady).length, 1);
        expect(outcomes.where((o) => o == SilentUpdateOutcome.alreadyInProgress).length, 1);
      });

      test('rejects appcast with external HTTP installer URL before starting installer', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'http://updates.example.com/PlugAgente-Setup-99.0.0.exe',
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

        expect(result.isError(), isTrue);
        expect(fakeInstaller.installCount, 0);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticValidationFailure,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.validationErrorCode, 'invalid_asset_url');
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            expect(failure, isA<domain.ValidationFailure>());
            final typedFailure = failure as domain.Failure;
            expect(typedFailure.message, contains('invalid installer URL'));
            expect(typedFailure.context['validation_code'], 'invalid_asset_url');
          },
        );
      });

      test('rejects appcast with non-windows sparkle os before starting installer', () async {
        final fakeProbe = FakeAppcastProbeService()
          ..result = const AppcastProbeResult(
            requestUrl: 'https://example.com/appcast.xml',
            latestVersion: '99.0.0+1',
            assetUrl: 'https://example.com/PlugAgente-Setup-99.0.0.exe',
            assetSize: 5,
            assetName: 'PlugAgente-Setup-99.0.0.exe',
            sha256: '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            os: 'macos',
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
        expect(fakeInstaller.installCount, 0);
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticValidationFailure,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.appcastProbeOs, 'macos');
        expect(orchestrator.lastAutomaticDiagnostics?.validationErrorCode, 'unsupported_os');
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            expect(failure, isA<domain.ValidationFailure>());
            final typedFailure = failure as domain.Failure;
            expect(typedFailure.message, contains('unsupported operating system'));
            expect(typedFailure.context['validation_code'], 'unsupported_os');
          },
        );
      });

      test('accepts appcast without sparkle os for legacy compatibility', () async {
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
        expect(fakeInstaller.installCount, 1);
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
          launcherStatusReader: const FileSilentUpdateLauncherStatusReader(),
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
          (outcome) => expect(outcome, SilentUpdateOutcome.rolloutSkipped),
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

      test('uses the same rollout bucket for diagnostics and eligibility check', () async {
        // Do NOT pre-seed the bucket — force first-generation path.
        final fakeProbe = FakeAppcastProbeService()
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
        final fakeInstaller = FakeSilentUpdateInstaller();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: fakeProbe,
          silentUpdateInstaller: fakeInstaller,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.checkSilently();

        final diag = orchestrator.lastAutomaticDiagnostics;
        expect(diag, isNotNull);
        final persistedBucket = settingsStore.getInt('auto_update.rollout_bucket');
        // rolloutBucket in diagnostics must equal the persisted bucket (same
        // value was used for both recording and eligibility).
        expect(diag!.rolloutBucket, persistedBucket);
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

      test('passes signature=false to silent installer when explicitly opted out', () async {
        dotenv.clean();
        dotenv.loadFromString(
          envString:
              'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml\n'
              'AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false',
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
        expect(fakeInstaller.request?.requireValidSignature, isFalse);
        expect(orchestrator.lastAutomaticDiagnostics?.signatureRequired, isFalse);
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
          (outcome) => expect(outcome, SilentUpdateOutcome.cooldownActive),
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

      test('re-enabling automatic silent updates schedules an immediate silent check', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
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

        await orchestrator.initialize();
        final result = await orchestrator.setAutomaticSilentUpdatesEnabled(true);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(result.isSuccess(), isTrue);
        expect(fakeGateway.interval, 0);
        expect(fakeInstaller.request?.version, '99.0.0+1');
      });

      test('keeps recent pending update when launcher status is still in progress', () async {
        final statusDir = Directory.systemTemp.createTempSync('plug_launcher_in_progress_test_');
        addTearDown(() {
          if (statusDir.existsSync()) {
            statusDir.deleteSync(recursive: true);
          }
        });
        final now = DateTime.now();
        final statusFile = File('${statusDir.path}${Platform.pathSeparator}launcher.status.json');
        statusFile.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'state': 'elevatedStarted',
            'strategy': SilentUpdateInstallStrategy.currentUserThenElevated.name,
            'installDirectory': r'C:\PlugAgente',
            'installerPath': r'C:\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
            'logPath': r'C:\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
            'elevatedRetryStarted': true,
            'appPid': 1234,
            'signatureStatus': 'valid',
            'signatureRequired': true,
            'actualSha256': '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
            'hashValidationStatus': 'valid',
            'installDirectoryWritable': true,
            'elevatedCancelled': false,
            'lastUpdatedAt': now.toIso8601String(),
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
            'startedAt': now.toIso8601String(),
          }),
        );
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: FakeAppcastProbeService(),
          silentUpdateInstaller: FakeSilentUpdateInstaller(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          // The default launcher status reader is a no-op so the
          // application layer stays free of dart:io. Tests that need
          // to drive the reconciler from an on-disk status file must
          // inject the file-backed implementation explicitly.
          launcherStatusReader: const FileSilentUpdateLauncherStatusReader(),
        );

        await orchestrator.startAutomaticChecks();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticInstallStarted,
        );
        expect(orchestrator.lastAutomaticDiagnostics?.launcherState, 'elevatedStarted');
        expect(orchestrator.lastAutomaticDiagnostics?.automaticFailureCount, isNull);
        expect(settingsStore.getString('auto_update.pending_silent_update'), isNotNull);
      });

      test('clears stale pending record without incrementing failure counter', () async {
        // Persist a pending record with explicit paths that do not exist on disk.
        // This simulates a previous install where the app was reinstalled to a
        // different directory, leaving the stored absolute paths invalid.
        final stalePending = <String, Object?>{
          'version': '99.0.0+1',
          'installerPath': r'C:\OldPath\PlugAgente\updates\PlugAgente-Setup-99.0.0.exe',
          'launcherPath': r'C:\OldPath\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.exe',
          'launcherStatusPath': r'C:\OldPath\PlugAgente\updates\PlugAgente-Update-Helper-99.0.0+1.status.json',
          'logPath': r'C:\OldPath\PlugAgente\updates\PlugAgente-Update-99.0.0+1.log',
          'installDirectory': r'C:\OldPath\PlugAgente',
          'strategy': 'currentUserThenElevated',
          'appPid': 9999,
          'updateDirectorySecurityStatus': 'restricted',
          'startedAt': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
        };
        await settingsStore.setString(
          'auto_update.pending_silent_update',
          jsonEncode(stalePending),
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
          // Reconciliation needs the real reader to verify the on-disk
          // artifacts; otherwise the no-op default would short-circuit
          // every path check to "does not exist" and could lead the
          // reconciler to a different code path.
          launcherStatusReader: const FileSilentUpdateLauncherStatusReader(),
        );

        // startAutomaticChecks calls _reconcilePendingSilentUpdate before checking.
        await orchestrator.startAutomaticChecks();

        // Stale pending should be cleared without incrementing the failure counter.
        expect(settingsStore.getInt('auto_update.automatic_failure_count'), isNull);
        expect(settingsStore.getString('auto_update.pending_silent_update'), isNull);
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
          await fakeGateway.emit(const UpdaterUpdateAvailable());
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, ManualCheckOutcome.updateAvailable),
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
          await fakeGateway.emit(const UpdaterUpdateNotAvailable());
        };

        await orchestrator.initialize();
        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        expect(fakeGateway.feedUrls, <String>['https://example.com/appcast.xml']);
      });

      test('returns ManualCheckOutcome.noUpdate when update is not available', () async {
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
          await fakeGateway.emit(const UpdaterUpdateNotAvailable());
        };

        final result = await orchestrator.checkManual();

        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, ManualCheckOutcome.noUpdate),
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
          await fakeGateway.emit(const UpdaterUpdateNotAvailable());
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
          await fakeGateway.emit(const UpdaterUpdateNotAvailable());
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
      test('calls allowQuitForUpdate before native updater quits the app', () async {
        var allowQuitCalled = false;
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          allowQuitForUpdate: () async {
            allowQuitCalled = true;
          },
        );

        // Wire the orchestrator's event subscription before emitting.
        await orchestrator.initialize();
        await fakeGateway.emit(const UpdaterBeforeQuitForUpdate());

        expect(allowQuitCalled, isTrue);
      });

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
          await fakeGateway.emit(const UpdaterCheckingForUpdate());
          await fakeGateway.emit(const UpdaterUpdateNotAvailable());
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
          await fakeGateway.emit(const UpdaterErrorEvent());
        };

        await orchestrator.checkInBackground();

        expect(
          orchestrator.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updaterError,
        );
        expect(metricsCollector.autoUpdateBackgroundCheckUpdaterErrorCount, 1);
      });

      test('background trigger timeout produces triggerFailure diagnostics', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final hang = Completer<void>();
        final fakeGateway = FakeAutoUpdaterGateway()
          ..onCheckForUpdates = () async {
            await hang.future;
          };
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          backgroundRetryLimit: 1,
          backgroundTriggerTimeout: const Duration(milliseconds: 50),
        );

        await orchestrator.initialize();
        await orchestrator.checkInBackground();

        expect(
          orchestrator.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.triggerFailure,
        );
        expect(
          orchestrator.lastBackgroundDiagnostics?.errorMessage,
          contains('TimeoutException'),
        );
        expect(metricsCollector.autoUpdateBackgroundCheckTriggerFailureCount, 1);
        // Release the hung future so the test does not leak it.
        hang.complete();
      });

      test('background retry delay keeps the loop going across attempts', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway()..checkError = Exception('background boom');
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          backgroundRetryBaseDelay: const Duration(milliseconds: 10),
          backgroundRetryJitterFactor: 0,
        );

        await orchestrator.initialize();
        await orchestrator.checkInBackground();

        // All retries failed (3 attempts by default), so the trigger failure
        // metric is bumped once per attempt.
        expect(metricsCollector.autoUpdateBackgroundCheckTriggerFailureCount, 3);
      });

      test('skips reentrant background check while another is in progress', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final pendingTrigger = Completer<void>();
        var triggerCount = 0;
        final fakeGateway = FakeAutoUpdaterGateway()
          ..onCheckForUpdates = () async {
            triggerCount++;
            await pendingTrigger.future;
          };
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();

        final firstCall = orchestrator.checkInBackground();
        await Future<void>.delayed(Duration.zero);
        final secondCall = orchestrator.checkInBackground();
        await Future<void>.delayed(Duration.zero);

        expect(triggerCount, 1, reason: 'second call must short-circuit while first is in flight');

        pendingTrigger.complete();
        await Future.wait(<Future<void>>[firstCall, secondCall]);

        final thirdCall = orchestrator.checkInBackground();
        await Future<void>.delayed(Duration.zero);
        await thirdCall;
        expect(triggerCount, 2, reason: 'guard must release after the first call completes');
      });
    });

    group('late WinSparkle callbacks', () {
      test('does not persist background diagnostics after manual check timed out', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          manualTriggerTimeout: const Duration(milliseconds: 50),
          manualCompletionTimeout: const Duration(milliseconds: 50),
        );

        await orchestrator.initialize();
        final result = await orchestrator.checkManual();
        expect(result.isError(), isTrue);
        final backgroundBefore = orchestrator.lastBackgroundDiagnostics;

        // A late onUpdaterUpdateAvailable arrives after the manual check
        // already finished by timeout. The drain window must absorb it.
        await fakeGateway.emit(const UpdaterUpdateAvailable());
        await fakeGateway.emit(const UpdaterUpdateNotAvailable());
        await fakeGateway.emit(const UpdaterErrorEvent());
        await fakeGateway.emit(const UpdaterCheckingForUpdate());

        expect(
          orchestrator.lastBackgroundDiagnostics,
          backgroundBefore,
          reason: 'late callbacks must not pollute background diagnostics',
        );
        expect(metricsCollector.autoUpdateBackgroundCheckUpdaterErrorCount, 0);
      });

      test('drain window expires so genuine background callbacks resume tracking', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          manualTriggerTimeout: const Duration(milliseconds: 20),
          manualCompletionTimeout: const Duration(milliseconds: 20),
          lateCallbackDrainWindow: const Duration(milliseconds: 50),
        );

        await orchestrator.initialize();
        await orchestrator.checkManual();

        await Future<void>.delayed(const Duration(milliseconds: 80));

        await fakeGateway.emit(const UpdaterUpdateNotAvailable());

        expect(
          orchestrator.lastBackgroundDiagnostics?.completionSource,
          UpdateCheckCompletionSource.updateNotAvailable,
        );
      });
    });

    group('routing via FakeSilentUpdateCoordinator', () {
      test('checkInBackground delegates to coordinator when silent updates are enabled', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        await orchestrator.initialize();
        await orchestrator.checkInBackground();

        expect(fakeCoordinator.checkSilentlyCallCount, 1);
      });

      test('checkInBackground uses Sparkle path when silent updates are disabled', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final fakeCoordinator = FakeSilentUpdateCoordinator()..automaticSilentUpdatesEnabledValue = false;
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        await orchestrator.initialize();
        await orchestrator.checkInBackground();

        expect(fakeCoordinator.checkSilentlyCallCount, 0);
        expect(fakeGateway.lastInBackground, isTrue);
      });

      test('startAutomaticChecks calls reconcilePendingAndSchedule on coordinator', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        await orchestrator.startAutomaticChecks();

        expect(fakeCoordinator.reconcilePendingAndScheduleCallCount, 1);
      });

      test('setAutomaticSilentUpdatesEnabled(true) calls coordinator.scheduleAndStart', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        await orchestrator.initialize();
        await orchestrator.setAutomaticSilentUpdatesEnabled(true);

        expect(fakeCoordinator.scheduleAndStartCallCount, 1);
        expect(fakeCoordinator.stopCallCount, 0);
      });

      test('setAutomaticSilentUpdatesEnabled(false) calls coordinator.stop', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        await orchestrator.initialize();
        await orchestrator.setAutomaticSilentUpdatesEnabled(false);

        expect(fakeCoordinator.stopCallCount, 1);
        expect(fakeCoordinator.scheduleAndStartCallCount, 0);
      });

      test('isSilentCheckInProgress delegates to coordinator', () {
        final fakeCoordinator = FakeSilentUpdateCoordinator()..setInProgress(true);
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        expect(orchestrator.isSilentCheckInProgress, isTrue);
        fakeCoordinator.setInProgress(false);
        expect(orchestrator.isSilentCheckInProgress, isFalse);
      });

      test('lastAutomaticDiagnostics delegates to coordinator', () {
        final diag = UpdateCheckDiagnostics(
          checkedAt: DateTime.now(),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );
        final fakeCoordinator = FakeSilentUpdateCoordinator()..lastAutomaticDiagnosticsValue = diag;
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticUpdateNotAvailable,
        );
      });

      test('hasUpdateAwaitingUserConsent is true when coordinator reports UAC-blocked update', () {
        final diag = UpdateCheckDiagnostics(
          checkedAt: DateTime.now(),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          completionSource: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
          updateAvailable: true,
          pendingVersion: '99.0.0+1',
        );
        final fakeCoordinator = FakeSilentUpdateCoordinator()..lastAutomaticDiagnosticsValue = diag;
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        expect(orchestrator.hasUpdateAwaitingUserConsent, isTrue);
      });

      test('hasUpdateAwaitingUserConsent is false when no diagnostics or different source', () {
        final fakeCoordinator = FakeSilentUpdateCoordinator();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        expect(orchestrator.hasUpdateAwaitingUserConsent, isFalse);

        fakeCoordinator.lastAutomaticDiagnosticsValue = UpdateCheckDiagnostics(
          checkedAt: DateTime.now(),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          completionSource: UpdateCheckCompletionSource.automaticInstallReady,
          updateAvailable: true,
        );

        expect(orchestrator.hasUpdateAwaitingUserConsent, isFalse);
      });

      test('applyAvailableUpdate forwards userInitiated=true and applies pending on success', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator()
          ..checkSilentlyResult = const Success(SilentUpdateOutcome.installerReady);
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        final result = await orchestrator.applyAvailableUpdate(
          noticeTitle: 'Updating',
          noticeBody: 'PlugAgente will restart',
        );

        expect(result.isSuccess(), isTrue);
        expect(fakeCoordinator.checkSilentlyCallCount, 1);
        expect(fakeCoordinator.lastCheckSilentlyUserInitiated, isTrue);
        expect(fakeCoordinator.applyPendingCallCount, 1);
        expect(fakeCoordinator.lastApplyNoticeTitle, 'Updating');
        expect(fakeCoordinator.lastApplyNoticeBody, 'PlugAgente will restart');
      });

      test('applyAvailableUpdate fails when download outcome is not installerReady', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator()
          ..checkSilentlyResult = const Success(SilentUpdateOutcome.noNewVersion);
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        final result = await orchestrator.applyAvailableUpdate();

        expect(result.isError(), isTrue);
        expect(fakeCoordinator.applyPendingCallCount, 0);
      });

      test('applyAvailableUpdate propagates download failure', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator()..checkSilentlyResult = Failure(Exception('boom'));
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        final result = await orchestrator.applyAvailableUpdate();

        expect(result.isError(), isTrue);
        expect(fakeCoordinator.applyPendingCallCount, 0);
      });
    });
  });
}
