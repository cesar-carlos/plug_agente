import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/repositories/i_update_preferences_repository.dart';
import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/core/settings/auto_update_settings_keys.dart';

/// Default key used to persist the silent update pending record inside
/// the global settings store. Kept stable so records written by previous
/// versions of the agent are still recoverable.
const String pendingSilentUpdateSettingsKey = AutoUpdateSettingsKeys.pendingSilentUpdate;

/// Pure-Dart store that reads/writes the pending record as JSON through
/// [IUpdatePreferencesRepository]. Lives in the application layer because it
/// has no `dart:io` dependency — the repository delegates to settings IO.
class SettingsBackedPendingSilentUpdateStore implements IPendingSilentUpdateStore {
  SettingsBackedPendingSilentUpdateStore({
    required IUpdatePreferencesRepository preferences,
  }) : _preferences = preferences;

  final IUpdatePreferencesRepository _preferences;

  @override
  Future<PendingSilentUpdate?> read() async {
    final raw = _preferences.readPendingSilentUpdateJson();
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PendingSilentUpdate.fromJson(decoded);
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Failed to parse pending silent update state',
        name: 'settings_backed_pending_silent_update_store',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  @override
  Future<void> write(PendingSilentUpdate pending) {
    return _preferences.writePendingSilentUpdateJson(jsonEncode(pending.toJson()));
  }

  @override
  Future<void> clear() => _preferences.clearPendingSilentUpdateJson();
}

/// In-memory implementation used by tests and fallback when no settings
/// store is wired. Keeps the coordinator independent of the persistence
/// strategy in unit tests.
class InMemoryPendingSilentUpdateStore implements IPendingSilentUpdateStore {
  PendingSilentUpdate? _pending;

  @override
  Future<PendingSilentUpdate?> read() async => _pending;

  @override
  Future<void> write(PendingSilentUpdate pending) async {
    _pending = pending;
  }

  @override
  Future<void> clear() async {
    _pending = null;
  }
}

/// No-op reader that always returns `null`. Tests / non-Windows runs
/// can inject it so the coordinator stays free of `dart:io` when the
/// helper status file is irrelevant.
class NoopSilentUpdateLauncherStatusReader implements ISilentUpdateLauncherStatusReader {
  const NoopSilentUpdateLauncherStatusReader();

  @override
  Future<SilentUpdateLauncherStatus?> read(String? statusPath) async => null;

  @override
  Future<bool> fileExists(String? path) async => false;
}
