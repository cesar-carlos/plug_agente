import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/appcast_probe_service.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_coordinator.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/application/services/updater_event.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/metrics/metrics_collector.dart';
import 'package:result_dart/result_dart.dart';

import '../../fakes/fake_silent_update_coordinator.dart';
import '../../fakes/in_memory_update_preferences_repository.dart';
import '../../helpers/auto_update_test_fakes.dart';

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

      test('delegates to silent update coordinator', () async {
        final fakeCoordinator = FakeSilentUpdateCoordinator()
          ..checkSilentlyResult = const Success(SilentUpdateOutcome.noNewVersion);
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
          silentUpdateCoordinator: fakeCoordinator,
        );

        final result = await orchestrator.checkSilently();

        expect(fakeCoordinator.checkSilentlyCallCount, 1);
        expect(result.isSuccess(), isTrue);
        result.fold(
          (outcome) => expect(outcome, SilentUpdateOutcome.noNewVersion),
          (_) => fail('Expected success'),
        );
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

      test('initialize returns typed ConfigurationFailure when gateway setup fails', () async {
        final fakeGateway = FakeAutoUpdaterGateway()..setFeedError = Exception('init failed');
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.initialize();

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (error) => expect(error, isA<domain.ConfigurationFailure>()),
        );
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

      test('background WinSparkle callbacks notify changes listeners', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        var changeCount = 0;
        orchestrator.changes.listen((_) => changeCount++);

        await orchestrator.initialize();
        fakeGateway.onCheckForUpdates = () async {
          await fakeGateway.emit(const UpdaterUpdateNotAvailable());
        };

        await orchestrator.checkInBackground();
        await Future<void>.delayed(Duration.zero);

        expect(changeCount, greaterThan(0));
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

      test('startAutomaticChecks skips WinSparkle when automatic and notifications are off', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        await settingsStore.setBool(AppSettingsKeys.updateNotificationsEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.startAutomaticChecks();
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(fakeGateway.lastInBackground, isNull);
        expect(fakeGateway.interval, 0);
      });

      test('checkInBackground is a no-op when notifications are disabled', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        await settingsStore.setBool(AppSettingsKeys.updateNotificationsEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();
        await orchestrator.checkInBackground();

        expect(fakeGateway.lastInBackground, isNull);
      });

      test('setUpdateNotificationsEnabled persists preference and disables WinSparkle interval', () async {
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
        expect(fakeGateway.interval, greaterThan(0));

        final result = await orchestrator.setUpdateNotificationsEnabled(false);

        expect(result.isSuccess(), isTrue);
        expect(settingsStore.getBool(AppSettingsKeys.updateNotificationsEnabled), isFalse);
        expect(orchestrator.updateNotificationsEnabled, isFalse);
        expect(fakeGateway.interval, 0);
      });

      test('setUpdateNotificationsEnabled(true) restores WinSparkle interval when automatic is off', () async {
        await settingsStore.setBool(AppSettingsKeys.automaticSilentUpdatesEnabled, false);
        await settingsStore.setBool(AppSettingsKeys.updateNotificationsEnabled, false);
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();
        expect(fakeGateway.interval, 0);

        final result = await orchestrator.setUpdateNotificationsEnabled(true);

        expect(result.isSuccess(), isTrue);
        expect(fakeGateway.interval, greaterThan(0));
      });

      test('applyManualOnlyUpdateMode disables both preferences and records metric', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        await orchestrator.initialize();
        final result = await orchestrator.applyManualOnlyUpdateMode();

        expect(result.isSuccess(), isTrue);
        expect(orchestrator.updateNotificationsEnabled, isFalse);
        expect(orchestrator.automaticSilentUpdatesEnabled, isFalse);
        expect(fakeGateway.interval, 0);
        expect(
          metricsCollector.getSnapshot()['auto_update_manual_only_mode_applied'],
          1,
        );
      });

      test('applyManualOnlyUpdateMode clears stale automatic diagnostics', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final diagnostics = UpdateCheckDiagnostics(
          checkedAt: DateTime(2026, 5, 14, 11, 20),
          configuredFeedUrl: 'https://example.com/appcast.xml',
          requestedFeedUrl: 'https://example.com/appcast.xml',
          currentVersion: '1.6.7+1',
          completedAt: DateTime(2026, 5, 14, 11, 21),
          completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
        );
        await settingsStore.setString(
          'auto_update.last_automatic_diagnostics',
          jsonEncode(diagnostics.toJson()),
        );
        final coordinator = SilentUpdateCoordinator(
          RuntimeCapabilities.full(),
          () => 'https://example.com/appcast.xml',
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
        );
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          silentUpdateCoordinator: coordinator,
        );

        await orchestrator.initialize();
        expect(
          orchestrator.lastAutomaticDiagnostics?.completionSource,
          UpdateCheckCompletionSource.automaticDownloadFailure,
        );

        final result = await orchestrator.applyManualOnlyUpdateMode();

        expect(result.isSuccess(), isTrue);
        expect(orchestrator.lastAutomaticDiagnostics, isNull);
        expect(settingsStore.getString('auto_update.last_automatic_diagnostics'), isNull);
      });

      test('setAutomaticSilentUpdatesEnabled notifies listeners', () async {
        final fakeGateway = FakeAutoUpdaterGateway();
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: fakeGateway,
          appcastProbeService: FakeAppcastProbeService(),
          settingsStore: settingsStore,
          metricsCollector: metricsCollector,
        );

        var changeCount = 0;
        orchestrator.changes.listen((_) => changeCount++);

        await orchestrator.setAutomaticSilentUpdatesEnabled(false);
        await Future<void>.delayed(Duration.zero);

        expect(changeCount, greaterThan(0));
      });

      test('setAutomaticSilentUpdatesEnabled surfaces ConfigurationFailure on persist error', () async {
        final preferences = InMemoryUpdatePreferencesRepository();
        preferences.forcedPersistError = StateError('disk full');
        final orchestrator = AutoUpdateOrchestrator(
          RuntimeCapabilities.full(),
          updaterGateway: FakeAutoUpdaterGateway(),
          appcastProbeService: FakeAppcastProbeService(),
          updatePreferencesRepository: preferences,
          metricsCollector: metricsCollector,
        );

        final result = await orchestrator.setAutomaticSilentUpdatesEnabled(false);

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected ConfigurationFailure'),
          (error) {
            expect(error, isA<domain.ConfigurationFailure>());
            expect((error as domain.Failure).message, contains('persist'));
          },
        );
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
