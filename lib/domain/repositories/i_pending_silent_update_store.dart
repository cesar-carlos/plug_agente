import 'package:plug_agente/domain/entities/pending_silent_update.dart';
import 'package:result_dart/result_dart.dart';

class PendingSilentUpdateSnapshot {
  const PendingSilentUpdateSnapshot(this.pending);
  final PendingSilentUpdate? pending;
}

abstract interface class IPendingSilentUpdateStore {
  Future<Result<PendingSilentUpdateSnapshot>> load();
  Future<Result<void>> save(PendingSilentUpdate pending);
  Future<Result<void>> remove();
}

/// Compatibility for callers whose enclosing operation already maps typed failures.
extension PendingSilentUpdateStoreAccess on IPendingSilentUpdateStore {
  Future<PendingSilentUpdate?> read() async => (await load()).getOrThrow().pending;
  Future<void> write(PendingSilentUpdate pending) async {
    (await save(pending)).getOrThrow();
  }

  Future<void> clear() async {
    (await remove()).getOrThrow();
  }
}

/// Reads the launcher status JSON written on disk by the external helper
/// process. Async to keep `dart:io` out of the coordinator.
abstract interface class ISilentUpdateLauncherStatusReader {
  /// Returns the parsed status, or `null` when:
  /// - [statusPath] is null/empty (no path persisted yet);
  /// - the status file does not exist (helper has not written yet);
  /// - the file is corrupted (logged at error level).
  Future<SilentUpdateLauncherStatus?> read(String? statusPath);

  /// Returns `true` when [path] points to an existing regular file.
  /// Used by the coordinator to decide whether artifacts are still on
  /// disk before treating a pending record as ready.
  Future<bool> fileExists(String? path);
}
