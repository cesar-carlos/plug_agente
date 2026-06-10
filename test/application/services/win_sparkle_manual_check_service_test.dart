import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/auto_update_orchestrator_options.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/win_sparkle_manual_check_service.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

import '../../helpers/auto_update_test_fakes.dart';

void main() {
  group('WinSparkleManualCheckService', () {
    test('returns configuration failure when feed URL is missing', () async {
      final service = WinSparkleManualCheckService(
        capabilities: RuntimeCapabilities.full(),
        updaterGateway: FakeAutoUpdaterGateway(),
        appcastProbeService: FakeAppcastProbeService(),
        preferences: UpdatePreferencesRepository(settingsStore: InMemoryAppSettingsStore()),
        options: AutoUpdateOrchestratorOptions(
          manualTriggerTimeout: const Duration(milliseconds: 50),
          manualCompletionTimeout: const Duration(milliseconds: 50),
        ),
      );

      final result = await service.checkManual(
        feedUrl: null,
        isInitialized: () => true,
        ensureInitialized: () async {},
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (error) => expect(error, isA<domain.ConfigurationFailure>()),
      );
    });

    test('completes manual check when updater reports update available', () async {
      final gateway = FakeAutoUpdaterGateway();
      final service = WinSparkleManualCheckService(
        capabilities: RuntimeCapabilities.full(),
        updaterGateway: gateway,
        appcastProbeService: FakeAppcastProbeService(),
        preferences: UpdatePreferencesRepository(settingsStore: InMemoryAppSettingsStore()),
        options: AutoUpdateOrchestratorOptions(
          manualTriggerTimeout: const Duration(milliseconds: 50),
          manualCompletionTimeout: const Duration(milliseconds: 50),
        ),
      );

      gateway.onCheckForUpdates = () async {
        service.onUpdaterUpdateAvailable(version: '2.0.0');
      };
      final result = await service.checkManual(
        feedUrl: 'https://example.com/appcast.xml',
        isInitialized: () => true,
        ensureInitialized: () async {},
      );

      expect(result.isSuccess(), isTrue);
      result.fold(
        (outcome) => expect(outcome, ManualCheckOutcome.updateAvailable),
        (_) => fail('Expected success'),
      );
      expect(
        service.lastManualDiagnostics?.completionSource,
        UpdateCheckCompletionSource.updateAvailable,
      );
    });
  });
}
