import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/settings/auto_update_settings_keys.dart';
import 'package:uuid/uuid.dart';

/// Generates time-ordered correlation IDs (UUIDv7) for each auto-update
/// cycle and persists a small ring buffer of recent IDs so operators can
/// correlate logs across boot sessions without setting up centralized
/// telemetry (which is planned in Fase 7).
class UpdateCheckIdRecorder {
  UpdateCheckIdRecorder({IAppSettingsStore? settingsStore, Uuid? uuid})
    : _settingsStore = settingsStore,
      _uuid = uuid ?? const Uuid();

  /// Max number of IDs the ring buffer retains. Older entries fall off the
  /// front; new IDs are appended at the back. 20 is enough to debug a
  /// flapping cycle without bloating settings storage.
  static const int maxBufferSize = 20;

  final IAppSettingsStore? _settingsStore;
  final Uuid _uuid;

  /// Serializes [record] invocations so concurrent calls cannot race
  /// the "read existing buffer / mutate / write back" sequence. Without
  /// this, two cycles starting at the same time (e.g. silent + manual)
  /// could each load the same prefix, append their own entry on top of
  /// it, and overwrite each other on flush — one of the IDs would be
  /// silently dropped.
  Future<void> _writeQueue = Future<void>.value();

  /// Returns a new UUIDv7 (time-ordered RFC 9562 §5.7).
  String newId() => _uuid.v7();

  /// Appends [id] to the persisted ring buffer. Best-effort: an IO error
  /// is logged but does not propagate, because the ID is also already
  /// embedded in the in-memory `UpdateCheckDiagnostics` for the caller.
  ///
  /// Calls are serialised through [_writeQueue] so concurrent invokers
  /// cannot lose entries through a read-modify-write race.
  Future<void> record(String id, {required String source}) {
    final store = _settingsStore;
    if (store == null) return Future<void>.value();
    final pending = _writeQueue
        .catchError((Object _, StackTrace _) {
          // Swallow the previous batch's error so the queue can continue
          // with the latest snapshot. The error was already logged when
          // it first happened.
        })
        .then((_) => _appendEntry(store, id: id, source: source));
    _writeQueue = pending;
    return pending;
  }

  Future<void> _appendEntry(
    IAppSettingsStore store, {
    required String id,
    required String source,
  }) async {
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
      await store.setString(AutoUpdateSettingsKeys.recentCheckIds, jsonEncode(existing));
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
    final raw = store.getString(AutoUpdateSettingsKeys.recentCheckIds);
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
