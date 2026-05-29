import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';

/// Reads the helper status JSON file from disk. Lives in the
/// infrastructure layer so `dart:io` does not leak into the coordinator.
class FileSilentUpdateLauncherStatusReader implements ISilentUpdateLauncherStatusReader {
  const FileSilentUpdateLauncherStatusReader();

  @override
  Future<SilentUpdateLauncherStatus?> read(String? statusPath) async {
    if (statusPath == null || statusPath.isEmpty) return null;
    try {
      final statusFile = File(statusPath);
      // The async variants are intentional: the coordinator runs inside
      // the Dart event loop on the UI isolate, and a blocking
      // `existsSync` / `readAsStringSync` would stall rebuilds during
      // probes/reconciles. The "slow async io" lint targets hot loops,
      // not single-shot reads like this one.
      // ignore: avoid_slow_async_io
      if (!await statusFile.exists()) return null;
      final raw = await statusFile.readAsString();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return SilentUpdateLauncherStatus.fromJson(decoded);
      }
    } on Exception catch (error, stackTrace) {
      developer.log(
        'Failed to read silent update launcher status',
        name: 'file_silent_update_launcher_status_reader',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  @override
  Future<bool> fileExists(String? path) async {
    if (path == null || path.isEmpty) return false;
    try {
      // See `read` for why the async API is preferred here.
      // ignore: avoid_slow_async_io
      return File(path).exists();
    } on Exception {
      return false;
    }
  }
}
