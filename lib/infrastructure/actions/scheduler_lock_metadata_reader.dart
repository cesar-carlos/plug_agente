import 'dart:io';

import 'package:plug_agente/infrastructure/actions/scheduler_lock_metadata.dart';

/// Reads key=value lines from the scheduler instance lock file.
class SchedulerLockMetadataReader {
  const SchedulerLockMetadataReader();

  Future<SchedulerLockMetadata?> read(String lockFilePath) async {
    final file = File(lockFilePath);
    if (!file.existsSync()) {
      return null;
    }

    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty) {
        return null;
      }

      final values = <String, String>{};
      for (final line in lines) {
        final separatorIndex = line.indexOf('=');
        if (separatorIndex <= 0 || separatorIndex >= line.length - 1) {
          continue;
        }
        final key = line.substring(0, separatorIndex).trim();
        final value = line.substring(separatorIndex + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          values[key] = value;
        }
      }

      return SchedulerLockMetadata(
        pid: int.tryParse(values['pid'] ?? ''),
        acquiredAt: DateTime.tryParse(values['acquired_at'] ?? ''),
        runtimeInstanceId: values['runtime_instance_id'],
        runtimeSessionId: values['runtime_session_id'],
      );
    } on FileSystemException {
      return null;
    }
  }

  Future<Map<String, Object?>> readDiagnosticsMap(String lockFilePath) async {
    final metadata = await read(lockFilePath);
    if (metadata == null) {
      return const <String, Object?>{};
    }

    return <String, Object?>{
      if (metadata.pid != null) 'lock_pid': '${metadata.pid}',
      if (metadata.acquiredAt != null) 'lock_acquired_at': metadata.acquiredAt!.toUtc().toIso8601String(),
      if (metadata.runtimeInstanceId != null) 'lock_runtime_instance_id': metadata.runtimeInstanceId,
      if (metadata.runtimeSessionId != null) 'lock_runtime_session_id': metadata.runtimeSessionId,
    };
  }
}
