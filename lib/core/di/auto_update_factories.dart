import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/repositories/i_pending_silent_update_store.dart';
import 'package:plug_agente/domain/services/i_appcast_probe_service.dart';
import 'package:plug_agente/infrastructure/repositories/settings_backed_pending_silent_update_store.dart';
import 'package:plug_agente/infrastructure/repositories/update_preferences_repository.dart';
import 'package:plug_agente/infrastructure/services/appcast_probe_service.dart';

IAppcastProbeService createAppcastProbeService() => AppcastProbeService();

IUpdatePreferencesRepository createUpdatePreferencesRepository(IAppSettingsStore store) =>
    UpdatePreferencesRepository(settingsStore: store);
IPendingSilentUpdateStore createPendingSilentUpdateStore(IUpdatePreferencesRepository preferences) =>
    SettingsBackedPendingSilentUpdateStore(preferences: preferences);
