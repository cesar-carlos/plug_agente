import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/silent_update_diagnostics_store.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/settings/auto_update_settings_keys.dart';

void main() {
  group('SilentUpdateDiagnosticsStore', () {
    late InMemoryAppSettingsStore settingsStore;
    late UpdatePreferencesRepository preferences;
    late SilentUpdateDiagnosticsStore store;

    setUp(() {
      settingsStore = InMemoryAppSettingsStore();
      preferences = UpdatePreferencesRepository(settingsStore: settingsStore);
      store = SilentUpdateDiagnosticsStore(preferences: preferences);
    });

    UpdateCheckDiagnostics awaitingConsentDiagnostics({
      required String pendingVersion,
    }) {
      return UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026, 6, 10, 12),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml',
        currentVersion: AppConstants.appVersion,
        completedAt: DateTime.utc(2026, 6, 10, 12, 5),
        completionSource: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        updateAvailable: true,
        pendingVersion: pendingVersion,
        remoteVersion: pendingVersion,
      );
    }

    test('reconcileStaleAwaitingConsent keeps newer pending version', () {
      final restored = awaitingConsentDiagnostics(pendingVersion: '99.0.0+1');

      final reconciled = store.reconcileStaleAwaitingConsent(restored);

      expect(reconciled.completionSource, UpdateCheckCompletionSource.automaticAwaitingUserConsent);
      expect(reconciled.pendingVersion, '99.0.0+1');
      expect(reconciled.updateAvailable, isTrue);
    });

    test('reconcileStaleAwaitingConsent drops stale pending equal to current version', () {
      final restored = awaitingConsentDiagnostics(pendingVersion: AppConstants.appVersion);

      final reconciled = store.reconcileStaleAwaitingConsent(restored);

      expect(reconciled.completionSource, UpdateCheckCompletionSource.automaticUpdateNotAvailable);
      expect(reconciled.updateAvailable, isFalse);
      expect(reconciled.pendingVersion, isNull);
    });

    test('reconcileStaleAwaitingConsent drops stale pending older than current version', () {
      final restored = awaitingConsentDiagnostics(pendingVersion: '0.1.0+1');

      final reconciled = store.reconcileStaleAwaitingConsent(restored);

      expect(reconciled.completionSource, UpdateCheckCompletionSource.automaticUpdateNotAvailable);
      expect(reconciled.updateAvailable, isFalse);
    });

    test('reconcileStaleAwaitingConsent leaves non-consent diagnostics unchanged', () {
      final restored = UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026, 6, 10, 12),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml',
        currentVersion: AppConstants.appVersion,
        completionSource: UpdateCheckCompletionSource.automaticInstallReady,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      );

      final reconciled = store.reconcileStaleAwaitingConsent(restored);

      expect(reconciled, same(restored));
    });

    test('persist writes JSON and clearPersisted removes it', () async {
      store.lastAutomaticDiagnostics = UpdateCheckDiagnostics(
        checkedAt: DateTime.utc(2026, 6, 10, 12),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml',
        currentVersion: AppConstants.appVersion,
        completionSource: UpdateCheckCompletionSource.automaticUpdateNotAvailable,
      );

      await store.persist();

      final raw = settingsStore.getString(AutoUpdateSettingsKeys.lastAutomaticDiagnostics);
      expect(raw, isNotNull);
      final decoded = jsonDecode(raw!) as Map<String, dynamic>;
      expect(decoded['configuredFeedUrl'], 'https://example.com/appcast.xml');

      await store.clearPersisted();

      expect(store.lastAutomaticDiagnostics, isNull);
      expect(settingsStore.getString(AutoUpdateSettingsKeys.lastAutomaticDiagnostics), isNull);
    });

    test('hydrate restores diagnostics and reconciles stale awaiting consent', () async {
      final stale = awaitingConsentDiagnostics(pendingVersion: AppConstants.appVersion);
      await preferences.writeLastAutomaticDiagnosticsJson(jsonEncode(stale.toJson()));

      store.hydrate();

      expect(store.lastAutomaticDiagnostics, isNotNull);
      expect(
        store.lastAutomaticDiagnostics?.completionSource,
        UpdateCheckCompletionSource.automaticUpdateNotAvailable,
      );
      expect(store.lastAutomaticDiagnostics?.updateAvailable, isFalse);
    });

    test('hydrate ignores invalid JSON', () async {
      await settingsStore.setString(
        AutoUpdateSettingsKeys.lastAutomaticDiagnostics,
        '{not-json',
      );

      store.hydrate();

      expect(store.lastAutomaticDiagnostics, isNull);
    });
  });
}
