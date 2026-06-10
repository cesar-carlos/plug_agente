import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/settings/auto_update_settings_keys.dart';

void main() {
  group('UpdatePreferencesRepository', () {
    late InMemoryAppSettingsStore store;
    late UpdatePreferencesRepository repository;

    setUp(() {
      store = InMemoryAppSettingsStore();
      repository = UpdatePreferencesRepository(settingsStore: store);
    });

    test('reads and writes notification preferences', () async {
      expect(repository.updateNotificationsEnabled, isTrue);
      await repository.setUpdateNotificationsEnabled(false);
      expect(repository.updateNotificationsEnabled, isFalse);
      expect(store.getBool(AppSettingsKeys.updateNotificationsEnabled), isFalse);
    });

    test('reads and writes automatic silent update preference', () async {
      expect(repository.automaticSilentUpdatesEnabled, isTrue);
      await repository.setAutomaticSilentUpdatesEnabled(false);
      expect(repository.automaticSilentUpdatesEnabled, isFalse);
      expect(store.getBool(AppSettingsKeys.automaticSilentUpdatesEnabled), isFalse);
    });

    test('persists manual and background diagnostics JSON', () async {
      final diagnostics = UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml',
        currentVersion: '1.0.0',
      );
      final encoded = jsonEncode(diagnostics.toJson());

      await repository.writeLastManualDiagnosticsJson(encoded);
      await repository.writeLastBackgroundDiagnosticsJson(encoded);

      expect(repository.readLastManualDiagnosticsJson(), encoded);
      expect(repository.readLastBackgroundDiagnosticsJson(), encoded);
      expect(store.getString(AutoUpdateSettingsKeys.lastManualDiagnostics), encoded);
    });

    test('persists automatic diagnostics and pending silent update JSON', () async {
      const automaticJson = '{"checkedAt":"2026-01-01T00:00:00.000Z"}';
      const pendingJson = '{"version":"9.9.9"}';

      await repository.writeLastAutomaticDiagnosticsJson(automaticJson);
      await repository.writePendingSilentUpdateJson(pendingJson);

      expect(repository.readLastAutomaticDiagnosticsJson(), automaticJson);
      expect(repository.readPendingSilentUpdateJson(), pendingJson);

      await repository.clearLastAutomaticDiagnosticsJson();
      await repository.clearPendingSilentUpdateJson();

      expect(repository.readLastAutomaticDiagnosticsJson(), isNull);
      expect(repository.readPendingSilentUpdateJson(), isNull);
    });

    test('persists rollout bucket', () async {
      await repository.writeRolloutBucket(42);
      expect(repository.readRolloutBucket(), 42);
      expect(store.getInt(AutoUpdateSettingsKeys.rolloutBucket), 42);
    });

    test('persists manual timeout circuit breaker state', () async {
      final persistence = repository.manualTimeoutCircuitPersistence();
      final cooldownUntil = DateTime.utc(2026, 6, 10, 13);

      await persistence.persistFailure(failureCount: 2, cooldownUntil: cooldownUntil);

      expect(persistence.failureCount, 2);
      expect(
        persistence.cooldownUntil?.millisecondsSinceEpoch,
        cooldownUntil.millisecondsSinceEpoch,
      );
      expect(store.getInt(AutoUpdateSettingsKeys.timeoutConsecutiveCount), 2);
      expect(
        store.getInt(AutoUpdateSettingsKeys.timeoutCooldownUntilMs),
        cooldownUntil.millisecondsSinceEpoch,
      );

      await persistence.clear();

      expect(persistence.failureCount, 0);
      expect(persistence.cooldownUntil, isNull);
      expect(store.containsKey(AutoUpdateSettingsKeys.timeoutConsecutiveCount), isFalse);
    });

    test('persists automatic failure circuit breaker state', () async {
      final persistence = repository.automaticFailureCircuitPersistence();

      await persistence.persistFailure(failureCount: 3);

      expect(persistence.failureCount, 3);
      expect(store.getInt(AutoUpdateSettingsKeys.automaticFailureCount), 3);
      expect(store.containsKey(AutoUpdateSettingsKeys.automaticCooldownUntilMs), isFalse);
    });
  });
}
