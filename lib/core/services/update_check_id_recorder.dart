import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:uuid/uuid.dart';

/// Generates time-ordered correlation IDs (UUIDv7) for each auto-update
/// cycle and persists a small ring buffer of recent IDs so operators can
/// correlate logs across boot sessions without setting up centralized
/// telemetry (which is planned in Fase 7).
class UpdateCheckIdRecorder {
  UpdateCheckIdRecorder({IAppSettingsStore? settingsStore, Uuid? uuid})
    : _settingsStore = settingsStore,
      _uuid = uuid ?? const Uuid();

  static const String _ringBufferKey = 'auto_update.recent_check_ids';

  /// Max number of IDs the ring buffer retains. Older entries fall off the
  /// front; new IDs are appended at the back. 20 is enough to debug a
  /// flapping cycle without bloating settings storage.
  static const int maxBufferSize = 20;

  final IAppSettingsStore? _settingsStore;
  final Uuid _uuid;

  /// Returns a new UUIDv7 (time-ordered RFC 9562 §5.7).
  String newId() => _uuid.v7();

  /// Appends [id] to the persisted ring buffer. Best-effort: an IO error
  /// is logged but does not propagate, because the ID is also already
  /// embedded in the in-memory `UpdateCheckDiagnostics` for the caller.
  Future<void> record(String id, {required String source}) async {
    final store = _settingsStore;
    if (store == null) return;
    try {
      final existing = _readBuffer(store);
      existing.add(<String, dynamic>{
        'id': id,
        'source': source,
        'at': DateTime.now().toIso8601String(),
      });
      while (existing.length > maxBufferSize) {
        existing.removeAt(0);
      }
      await store.setString(_ringBufferKey, jsonEncode(existing));
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to persist auto-update check id ring buffer entry',
        name: 'update_check_id_recorder',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Returns the persisted ring buffer entries in order (oldest first).
  /// Each entry is a `Map<String, dynamic>` with keys `id`, `source`, `at`.
  List<Map<String, dynamic>> recent() {
    final store = _settingsStore;
    if (store == null) return const <Map<String, dynamic>>[];
    try {
      final raw = _readBuffer(store);
      return raw.whereType<Map<String, dynamic>>().toList(growable: false);
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to read auto-update check id ring buffer',
        name: 'update_check_id_recorder',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
      return const <Map<String, dynamic>>[];
    }
  }

  List<dynamic> _readBuffer(IAppSettingsStore store) {
    final raw = store.getString(_ringBufferKey);
    if (raw == null || raw.isEmpty) return <dynamic>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return List<dynamic>.from(decoded);
    } on FormatException {
      // Corrupted buffer: clear and start fresh on next write.
    }
    return <dynamic>[];
  }
}
