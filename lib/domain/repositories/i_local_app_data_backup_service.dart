import 'package:plug_agente/domain/backup/local_data_backup.dart';
import 'package:result_dart/result_dart.dart';

abstract class ILocalAppDataBackupService {
  /// Drift / `PRAGMA user_version` of the live `agent_config` database.
  int get liveAgentConfigSchemaVersion;

  Future<Result<void>> exportBackupZip(String destinationZipPath);

  Future<Result<RestoreStagingSnapshot>> stageRestoreFromZip(String zipPath);

  Future<Result<void>> applyRestore(RestoreStagingSnapshot staging);

  /// Persists a short technical summary when a restore fails after the UI has
  /// been torn down, so the next launch can surface what went wrong.
  Future<void> writeRestoreFailureDiagnostics(Object failure);

  /// Reads the diagnostics written by a previous failed restore, if any.
  /// Returns null when there is nothing pending to surface.
  Future<String?> readPendingRestoreFailureDiagnostics();

  /// Clears the pending restore failure diagnostics once the user has seen it.
  Future<void> clearRestoreFailureDiagnostics();

  void disposeStaging(RestoreStagingSnapshot staging);
}
