import 'dart:developer' as developer;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/application/repositories/i_app_preferences_repository.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._preferences) {
    _isDarkMode = _preferences.isDarkModeEnabled;
  }

  final IAppPreferencesRepository _preferences;
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
      await _preferences.setIsDarkModeEnabled(value);
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
