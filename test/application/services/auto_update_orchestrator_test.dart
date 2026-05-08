import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';

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
    itemCount: 1,
  );
  String? lastProbeUrl;

  @override
  Future<AppcastProbeResult> probeLatest({
    required String feedUrl,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastProbeUrl = feedUrl;
    return AppcastProbeResult(
      requestUrl: feedUrl,
      latestVersion: result.latestVersion,
      itemCount: result.itemCount,
      errorMessage: result.errorMessage,
    );
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
        expect(fakeGateway.interval, 3600);
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
        expect(fakeGateway.lastInBackground, isFalse);
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
        expect(fakeGateway.lastInBackground, isFalse);
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
        expect(fakeGateway.lastInBackground, isFalse);
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
