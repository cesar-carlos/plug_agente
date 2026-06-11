import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/query_request.dart';

const playgroundStreamingModeKey = 'playground_streaming_mode_enabled';
const playgroundSqlHandlingModeKey = 'playground_sql_handling_mode';

/// Persists playground SQL handling and streaming mode preferences.
///
/// Extracted from the playground page so settings restore/save stays testable
/// without widget scaffolding.
class PlaygroundPageSettingsController {
  const PlaygroundPageSettingsController();

  Future<bool> restoreStreamingMode(IAppSettingsStore? store) async {
    if (store == null) {
      return false;
    }
    return store.getBool(playgroundStreamingModeKey) ?? false;
  }

  Future<void> saveStreamingMode(IAppSettingsStore? store, bool enabled) async {
    if (store == null) {
      return;
    }
    await store.setBool(playgroundStreamingModeKey, enabled);
  }

  Future<SqlHandlingMode> restoreSqlHandlingMode(IAppSettingsStore? store) async {
    if (store == null) {
      return SqlHandlingMode.managed;
    }
    final preserve = store.getBool(playgroundSqlHandlingModeKey) ?? false;
    return preserve ? SqlHandlingMode.preserve : SqlHandlingMode.managed;
  }

  Future<void> saveSqlHandlingMode(IAppSettingsStore? store, bool preserve) async {
    if (store == null) {
      return;
    }
    await store.setBool(playgroundSqlHandlingModeKey, preserve);
  }

  Future<void> restoreStreamingModeSafely(
    IAppSettingsStore? store,
    void Function(bool enabled) apply,
  ) async {
    try {
      apply(await restoreStreamingMode(store));
    } on Object catch (error) {
      AppLogger.warning('Failed to restore streaming mode', error);
    }
  }

  Future<void> restoreSqlHandlingModeSafely(
    IAppSettingsStore? store,
    void Function(SqlHandlingMode mode) apply,
  ) async {
    try {
      apply(await restoreSqlHandlingMode(store));
    } on Object catch (error) {
      AppLogger.warning('Failed to restore SQL handling mode', error);
    }
  }

  Future<void> saveStreamingModeSafely(IAppSettingsStore? store, bool enabled) async {
    try {
      await saveStreamingMode(store, enabled);
    } on Object catch (error) {
      AppLogger.warning('Failed to sync streaming mode with preserve', error);
    }
  }
}
