import 'dart:developer' as developer;
import 'dart:io';

import 'package:plug_agente/infrastructure/actions/scheduler_lock_metadata_reader.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_lifetime_checker.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';

/// Removes a scheduler lock file when the owning process is no longer running.
class SchedulerStaleLockRecovery {
  SchedulerStaleLockRecovery({
    SchedulerLockMetadataReader? metadataReader,
    WindowsProcessLifetimeChecker? processLifetimeChecker,
    GlobalStorageAclBootstrap? aclBootstrap,
    int Function()? currentPid,
  }) : _metadataReader = metadataReader ?? const SchedulerLockMetadataReader(),
       _processLifetimeChecker = processLifetimeChecker ?? WindowsProcessLifetimeChecker(),
       _aclBootstrap = aclBootstrap ?? GlobalStorageAclBootstrap(),
       _currentPid = currentPid ?? _currentProcessPid;

  static const String _logName = 'scheduler_stale_lock_recovery';

  static int _currentProcessPid() => pid;

  final SchedulerLockMetadataReader _metadataReader;
  final WindowsProcessLifetimeChecker _processLifetimeChecker;
  final GlobalStorageAclBootstrap _aclBootstrap;
  final int Function() _currentPid;

  Future<bool> tryRemoveStaleLock({
    required String lockFilePath,
    required String appDirectoryPath,
  }) async {
    final file = File(lockFilePath);
    if (!file.existsSync()) {
      return false;
    }

    final metadata = await _metadataReader.read(lockFilePath);
    final lockPid = metadata?.pid;
    if (lockPid == null || lockPid == _currentPid()) {
      return false;
    }

    if (await _processLifetimeChecker.isProcessRunning(lockPid)) {
      return false;
    }

    await _aclBootstrap.ensureDirectoryAcls(appDirectoryPath);
    await _aclBootstrap.normalizeLockFile(lockFilePath);

    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
      developer.log(
        'Removed stale scheduler lock file after process $lockPid exited',
        name: _logName,
        level: 800,
      );
      return true;
    } on FileSystemException catch (error, stackTrace) {
      developer.log(
        'Unable to delete stale scheduler lock file',
        name: _logName,
        error: error,
        stackTrace: stackTrace,
        level: 900,
      );
      return false;
    }
  }
}
