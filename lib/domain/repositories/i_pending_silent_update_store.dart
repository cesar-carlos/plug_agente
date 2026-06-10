import 'package:plug_agente/domain/entities/pending_silent_update.dart';

/// Persistence boundary for the silent update pending record and the
/// helper status file. Hides `dart:io` and the raw settings key from the
/// coordinator so the application layer stays free of infrastructure
/// concerns and the orchestrator becomes testable with simple fakes.
///
/// Implementations MUST be tolerant to:
/// - missing files / first run (return `null`);
/// - corrupted JSON (log and return `null`);
/// - concurrent reads (no locking guarantees — readers should assume the
///   latest persisted snapshot).
abstract interface class IPendingSilentUpdateStore {
  /// Returns the most recent pending record, or `null` when no silent
  /// update is in flight.
  Future<PendingSilentUpdate?> read();

  /// Persists [pending] as the active in-flight record. Overwrites any
  /// previous entry. Implementations should fsync best-effort: callers
  /// may follow up with `IAppSettingsStore.flushPendingPersistence` when
  /// they need durability before the next step.
  Future<void> write(PendingSilentUpdate pending);

  /// Clears the active record so the next `read` returns `null`.
  Future<void> clear();
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
