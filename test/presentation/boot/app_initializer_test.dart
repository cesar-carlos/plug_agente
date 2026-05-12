import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/presentation/boot/app_initializer.dart';

void main() {
  group('resolveStartupWindowPreferences', () {
    test('should return defaults when settings are missing', () {
      final prefs = InMemoryAppSettingsStore();

      final preferences = resolveStartupWindowPreferences(prefs);

      check(preferences.startMinimized).isFalse();
      check(preferences.minimizeToTray).isTrue();
      check(preferences.closeToTray).isTrue();
    });

    test('should return saved values from settings store', () async {
      final prefs = InMemoryAppSettingsStore();
      await prefs.setBool(AppSettingsKeys.startMinimized, true);
      await prefs.setBool(AppSettingsKeys.minimizeToTray, false);
      await prefs.setBool(AppSettingsKeys.closeToTray, false);

      final preferences = resolveStartupWindowPreferences(prefs);

      check(preferences.startMinimized).isTrue();
      check(preferences.minimizeToTray).isFalse();
      check(preferences.closeToTray).isFalse();
    });

    test('should disable start minimized when tray restore is unavailable', () async {
      final prefs = InMemoryAppSettingsStore();
      await prefs.setBool(AppSettingsKeys.startMinimized, true);

      final preferences = resolveStartupWindowPreferences(
        prefs,
        canStartMinimized: false,
      );

      check(preferences.startMinimized).isFalse();
      check(preferences.minimizeToTray).isTrue();
      check(preferences.closeToTray).isTrue();
    });
  });
}
