import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator_options.dart';
import 'package:plug_agente/application/services/retry_policy.dart';
import 'package:plug_agente/application/services/win_sparkle_background_check_service.dart';
import 'package:plug_agente/application/services/win_sparkle_manual_check_service.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

import '../../helpers/auto_update_test_fakes.dart';

void main() {
  group('WinSparkleBackgroundCheckService', () {
    late FakeAutoUpdaterGateway gateway;
    late UpdatePreferencesRepository preferences;
    late WinSparkleManualCheckService manualCheckService;
    late WinSparkleBackgroundCheckService service;

    WinSparkleBackgroundCheckService buildService({
      AutoUpdateOrchestratorOptions? options,
      DateTime Function()? clock,
    }) {
      return WinSparkleBackgroundCheckService(
        updaterGateway: gateway,
        preferences: preferences,
        manualCheckService: manualCheckService,
        options: options ??
            AutoUpdateOrchestratorOptions(
              backgroundRetry: RetryPolicy(
                attemptLimit: 1,
                baseDelay: Duration.zero,
                triggerTimeout: const Duration(milliseconds: 50),
              ),
            ),
        clock: clock ?? () => DateTime.utc(2026, 6, 10, 12),
        feedUrlResolver: () => 'https://example.com/appcast.xml',
      );
    }

    setUp(() {
      gateway = FakeAutoUpdaterGateway();
      preferences = UpdatePreferencesRepository(settingsStore: InMemoryAppSettingsStore());
      manualCheckService = WinSparkleManualCheckService(
        capabilities: RuntimeCapabilities.full(),
        updaterGateway: gateway,
        appcastProbeService: FakeAppcastProbeService(),
        preferences: preferences,
        options: AutoUpdateOrchestratorOptions(
          manualTriggerTimeout: const Duration(milliseconds: 50),
          manualCompletionTimeout: const Duration(milliseconds: 50),
        ),
      );
      service = buildService();
    });

    test('skips when updater is unavailable', () async {
      await service.checkInBackground(
        isAvailable: false,
        automaticSilentUpdatesEnabled: false,
        feedUrl: 'https://example.com/appcast.xml',
      );

      expect(gateway.lastInBackground, isNull);
    });

    test('skips when automatic silent updates are enabled', () async {
      await service.checkInBackground(
        isAvailable: true,
        automaticSilentUpdatesEnabled: true,
        feedUrl: 'https://example.com/appcast.xml',
      );

      expect(gateway.lastInBackground, isNull);
    });

    test('skips when update notifications are disabled', () async {
      await preferences.setUpdateNotificationsEnabled(false);

      await service.checkInBackground(
        isAvailable: true,
        automaticSilentUpdatesEnabled: false,
        feedUrl: 'https://example.com/appcast.xml',
      );

      expect(gateway.lastInBackground, isNull);
    });

    test('skips when feed URL is null', () async {
      await service.checkInBackground(
        isAvailable: true,
        automaticSilentUpdatesEnabled: false,
        feedUrl: null,
      );

      expect(gateway.lastInBackground, isNull);
    });

    test('triggers background check when preconditions are met', () async {
      gateway.onCheckForUpdates = () async {};

      await service.checkInBackground(
        isAvailable: true,
        automaticSilentUpdatesEnabled: false,
        feedUrl: 'https://example.com/appcast.xml',
      );

      expect(gateway.lastInBackground, isTrue);
      expect(service.lastBackgroundDiagnostics?.configuredFeedUrl, 'https://example.com/appcast.xml');
      expect(service.lastBackgroundDiagnostics?.triggerCompletedAt, isNotNull);
    });

    test('records trigger failure diagnostics when checkForUpdates throws', () async {
      gateway.checkError = Exception('trigger failed');

      await service.checkInBackground(
        isAvailable: true,
        automaticSilentUpdatesEnabled: false,
        feedUrl: 'https://example.com/appcast.xml',
      );

      expect(
        service.lastBackgroundDiagnostics?.completionSource,
        UpdateCheckCompletionSource.triggerFailure,
      );
      expect(service.lastBackgroundDiagnostics?.errorMessage, contains('trigger failed'));
    });

    test('onUpdaterUpdateAvailable records update available diagnostics', () {
      service.onUpdaterUpdateAvailable(version: '2.0.0', displayVersion: '2.0.0');

      expect(
        service.lastBackgroundDiagnostics?.completionSource,
        UpdateCheckCompletionSource.updateAvailable,
      );
      expect(service.lastBackgroundDiagnostics?.updateAvailable, isTrue);
      expect(service.lastBackgroundDiagnostics?.remoteVersion, '2.0.0');
    });

    test('onUpdaterUpdateNotAvailable records no-update diagnostics', () {
      service.onUpdaterUpdateNotAvailable(errorMessage: 'none');

      expect(
        service.lastBackgroundDiagnostics?.completionSource,
        UpdateCheckCompletionSource.updateNotAvailable,
      );
      expect(service.lastBackgroundDiagnostics?.updateAvailable, isFalse);
      expect(service.lastBackgroundDiagnostics?.errorMessage, 'none');
    });

    test('onUpdaterError records updater error diagnostics', () {
      service.onUpdaterError('network down');

      expect(
        service.lastBackgroundDiagnostics?.completionSource,
        UpdateCheckCompletionSource.updaterError,
      );
      expect(service.lastBackgroundDiagnostics?.errorMessage, 'network down');
    });

    test('ignores late callbacks during manual late-callback drain window', () async {
      gateway.onCheckForUpdates = () async {
        await Future<void>.delayed(const Duration(seconds: 5));
      };

      final result = await manualCheckService.checkManual(
        feedUrl: 'https://example.com/appcast.xml',
        isInitialized: () => true,
        ensureInitialized: () async {},
      );
      expect(result.isError(), isTrue);
      final before = service.lastBackgroundDiagnostics;

      service.onUpdaterUpdateAvailable(version: '9.9.9');

      expect(service.lastBackgroundDiagnostics, before);
    });
  });
}
