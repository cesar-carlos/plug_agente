import 'package:fluent_ui/fluent_ui.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._prefs) {
    _isDarkMode = _prefs.getBool(AppSettingsKeys.isDarkModeEnabled) ?? true;
  }

  final IAppSettingsStore _prefs;
  late bool _isDarkMode;

  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> setIsDarkMode(bool value) async {
    if (_isDarkMode == value) {
      return;
    }

    await _prefs.setBool(AppSettingsKeys.isDarkModeEnabled, value);
    _isDarkMode = value;
    notifyListeners();
  }
}
