import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';

/// Unified entry point for operator-facing app preferences.
///
/// Theme is owned here; startup/tray and auto-update prefs delegate to their
/// focused repositories so existing use cases and services stay unchanged.
abstract interface class IAppPreferencesRepository {
  bool get isDarkModeEnabled;

  Future<void> setIsDarkModeEnabled(bool enabled);

  IStartupPreferencesRepository get startup;

  IUpdatePreferencesRepository get updates;
}
