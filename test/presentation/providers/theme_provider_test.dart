import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';

class _ThrowingOnBoolSettingsStore extends InMemoryAppSettingsStore {
  @override
  Future<void> setBool(String key, bool value) async {
    throw const FileSystemException('disk full');
  }
}

void main() {
  group('ThemeProvider', () {
    test('defaults to dark mode when no preference is stored', () {
      final provider = ThemeProvider(InMemoryAppSettingsStore());

      expect(provider.isDarkMode, isTrue);
      expect(provider.themeMode, ThemeMode.dark);
      expect(provider.persistenceError, isNull);
    });

    test('reads the persisted preference on construction', () {
      final provider = ThemeProvider(
        InMemoryAppSettingsStore(<String, Object>{
          AppSettingsKeys.isDarkModeEnabled: false,
        }),
      );

      expect(provider.isDarkMode, isFalse);
      expect(provider.themeMode, ThemeMode.light);
    });

    test('persists and notifies on a successful change', () async {
      final store = InMemoryAppSettingsStore();
      final provider = ThemeProvider(store);
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setIsDarkMode(false);

      expect(provider.isDarkMode, isFalse);
      expect(store.getBool(AppSettingsKeys.isDarkModeEnabled), isFalse);
      expect(provider.persistenceError, isNull);
      expect(notifications, 1);
    });

    test('is a no-op when the value does not change', () async {
      final provider = ThemeProvider(InMemoryAppSettingsStore());
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setIsDarkMode(true);

      expect(notifications, 0);
      expect(provider.persistenceError, isNull);
    });

    test('keeps the previous value and exposes a typed error on persistence failure', () async {
      final provider = ThemeProvider(_ThrowingOnBoolSettingsStore());
      var notifications = 0;
      provider.addListener(() => notifications++);

      await provider.setIsDarkMode(false);

      expect(provider.isDarkMode, isTrue, reason: 'value must not flip when persistence fails');
      expect(provider.persistenceError, isNotNull);
      expect(
        provider.persistenceError!.code,
        SystemSettingsErrorCode.settingsPersistenceFailed,
      );
      expect(notifications, 1);
    });

    test('clearPersistenceError resets the error and notifies', () async {
      final provider = ThemeProvider(_ThrowingOnBoolSettingsStore());
      await provider.setIsDarkMode(false);
      expect(provider.persistenceError, isNotNull);

      var notifications = 0;
      provider.addListener(() => notifications++);

      provider.clearPersistenceError();

      expect(provider.persistenceError, isNull);
      expect(notifications, 1);
    });
  });
}
