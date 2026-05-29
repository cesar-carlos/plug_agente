import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._prefs) {
    _isDarkMode = _prefs.getBool(AppSettingsKeys.isDarkModeEnabled) ?? true;
  }

  final IAppSettingsStore _prefs;
  late bool _isDarkMode;
  SystemSettingsErrorState? _persistenceError;

  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  /// Typed error from the most recent failed persistence attempt, or null when
  /// the last change was saved successfully.
  SystemSettingsErrorState? get persistenceError => _persistenceError;

  void clearPersistenceError() {
    if (_persistenceError != null) {
      _persistenceError = null;
      notifyListeners();
    }
  }

  Future<void> setIsDarkMode(bool value) async {
    if (_isDarkMode == value) {
      return;
    }

    try {
      await _prefs.setBool(AppSettingsKeys.isDarkModeEnabled, value);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to persist dark mode preference',
        name: 'theme_provider',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      _persistenceError = SystemSettingsErrorState(
        code: SystemSettingsErrorCode.settingsPersistenceFailed,
        detail: error.toString(),
      );
      notifyListeners();
      return;
    }

    _persistenceError = null;
    _isDarkMode = value;
    notifyListeners();
  }
}
