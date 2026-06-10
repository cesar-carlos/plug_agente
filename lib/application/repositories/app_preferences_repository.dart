import 'package:plug_agente/application/repositories/i_app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';

class AppPreferencesRepository implements IAppPreferencesRepository {
  AppPreferencesRepository({
    required IAppSettingsStore settingsStore,
    required IStartupPreferencesRepository startup,
    required IUpdatePreferencesRepository updates,
  }) : _settingsStore = settingsStore,
       _startup = startup,
       _updates = updates;

  final IAppSettingsStore _settingsStore;
  final IStartupPreferencesRepository _startup;
  final IUpdatePreferencesRepository _updates;

  @override
  bool get isDarkModeEnabled =>
      _settingsStore.getBool(AppSettingsKeys.isDarkModeEnabled) ?? true;

  @override
  Future<void> setIsDarkModeEnabled(bool enabled) =>
      _settingsStore.setBool(AppSettingsKeys.isDarkModeEnabled, enabled);

  @override
  IStartupPreferencesRepository get startup => _startup;

  @override
  IUpdatePreferencesRepository get updates => _updates;
}
