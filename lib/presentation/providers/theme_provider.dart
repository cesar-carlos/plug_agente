import 'package:fluent_ui/fluent_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._prefs) {
    _isDarkMode = _prefs.getBool(_isDarkModeKey) ?? true;
  }

  static const String _isDarkModeKey = 'settings.is_dark_mode_enabled';

  final SharedPreferences _prefs;
  late bool _isDarkMode;

  bool get isDarkMode => _isDarkMode;

  ThemeMode get themeMode => _isDarkMode ? ThemeMode.dark : ThemeMode.light;

  Future<void> setIsDarkMode(bool value) async {
    if (_isDarkMode == value) {
      return;
    }

    _isDarkMode = value;
    notifyListeners();
    await _prefs.setBool(_isDarkModeKey, value);
  }
}
