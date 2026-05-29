import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';

/// Default key used to persist the silent update pending record inside
/// the global settings store. Kept stable so records written by previous
/// versions of the agent are still recoverable.
const String pendingSilentUpdateSettingsKey = 'auto_update.pending_silent_update';

/// Pure-Dart store that reads/writes the pending record as JSON inside
/// [IAppSettingsStore]. Lives in the application layer because it has no
/// `dart:io` dependency — the settings store itself owns the file IO.
class SettingsBackedPendingSilentUpdateStore implements IPendingSilentUpdateStore {
  SettingsBackedPendingSilentUpdateStore({
    required IAppSettingsStore settingsStore,
    String storageKey = pendingSilentUpdateSettingsKey,
  }) : _settingsStore = settingsStore,
       _storageKey = storageKey;

  final IAppSettingsStore _settingsStore;
  final String _storageKey;

  @override
  Future<PendingSilentUpdate?> read() async {
    final raw = _settingsStore.getString(_storageKey);
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
    return _settingsStore.setString(_storageKey, jsonEncode(pending.toJson()));
  }

  @override
  Future<void> clear() => _settingsStore.remove(_storageKey);
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
