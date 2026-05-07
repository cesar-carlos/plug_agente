import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/backup/local_backup_error_codes.dart';
import 'package:plug_agente/domain/errors/failures.dart';

/// Persists a short technical summary when restore fails after the UI is torn down.
abstract final class RestoreFailureDiagnostics {
  static Future<void> writeFromFailure({
    required GlobalStorageContext storage,
    required Object failure,
  }) async {
    try {
      final path = p.join(storage.appDirectoryPath, AppConstants.lastRestoreErrorFileName);
      final buffer = StringBuffer()
        ..writeln('Plug Agente — restore failure')
        ..writeln(DateTime.now().toUtc().toIso8601String())
        ..writeln();
      if (failure is Failure) {
        buffer
          ..writeln('code: ${failure.code}')
          ..writeln('message: ${failure.message}');
        final cause = failure.cause;
        if (cause != null) {
          buffer.writeln('cause: $cause');
        }
        final backupErr = failure.context[LocalBackupErrorCodes.contextKey];
        if (backupErr != null) {
          buffer.writeln('backupError: $backupErr');
        }
      } else {
        buffer.writeln(failure.toString());
      }
      await File(path).writeAsString(buffer.toString(), flush: true);
      developer.log(
        'wrote ${AppConstants.lastRestoreErrorFileName}',
        name: 'restore_failure_diagnostics',
      );
    } on Object catch (e, st) {
      developer.log(
        'failed to write ${AppConstants.lastRestoreErrorFileName}',
        name: 'restore_failure_diagnostics',
        error: e,
        stackTrace: st,
      );
    }
  }
}
