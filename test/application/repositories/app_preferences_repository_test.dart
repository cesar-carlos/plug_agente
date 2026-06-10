import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/repositories/app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/infrastructure/repositories/startup_preferences_repository.dart';

void main() {
  group('AppPreferencesRepository', () {
    late InMemoryAppSettingsStore store;
    late AppPreferencesRepository repository;

    setUp(() {
      store = InMemoryAppSettingsStore();
      repository = AppPreferencesRepository(
        settingsStore: store,
        startup: StartupPreferencesRepository(store),
        updates: UpdatePreferencesRepository(settingsStore: store),
      );
    });

    test('reads and writes dark mode preference', () async {
      expect(repository.isDarkModeEnabled, isTrue);

      await repository.setIsDarkModeEnabled(false);

      expect(repository.isDarkModeEnabled, isFalse);
      expect(store.getBool(AppSettingsKeys.isDarkModeEnabled), isFalse);
    });

    test('exposes startup preferences delegate', () {
      expect(repository.startup.startWithWindows, isFalse);
      expect(repository.startup.minimizeToTray, isTrue);
    });

    test('exposes update preferences delegate', () {
      expect(repository.updates.updateNotificationsEnabled, isTrue);
      expect(repository.updates.automaticSilentUpdatesEnabled, isTrue);
    });
  });
}
