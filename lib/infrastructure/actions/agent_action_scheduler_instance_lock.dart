import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_lock_failure_resolver.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_lock_metadata_reader.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_stale_lock_recovery.dart';
import 'package:plug_agente/infrastructure/actions/windows_process_lifetime_checker.dart';
import 'package:plug_agente/infrastructure/storage/global_storage_acl_bootstrap.dart';
import 'package:result_dart/result_dart.dart';

typedef SchedulerLockDirectoryEnsurer = Future<void> Function(Directory directory);
typedef SchedulerLockFileOpener = Future<RandomAccessFile> Function(File file);

/// File-backed exclusive lock for the agent action trigger scheduler.
class AgentActionSchedulerInstanceLock implements IAgentActionSchedulerInstanceLock {
  AgentActionSchedulerInstanceLock({
    required GlobalStorageContext storageContext,
    AgentRuntimeIdentity? runtimeIdentity,
    int Function()? currentPid,
    SchedulerLockDirectoryEnsurer? ensureParentDirectory,
    SchedulerLockFileOpener? openLockFile,
    GlobalStorageAclBootstrap? aclBootstrap,
    SchedulerLockMetadataReader? metadataReader,
    SchedulerStaleLockRecovery? staleLockRecovery,
    SchedulerLockFailureResolver? failureResolver,
    WindowsProcessLifetimeChecker? processLifetimeChecker,
  }) : _lockFilePath = p.join(storageContext.appDirectoryPath, AgentActionTriggerConstants.schedulerLockFileName),
       _appDirectoryPath = storageContext.appDirectoryPath,
       _runtimeIdentity = runtimeIdentity,
       _currentPid = currentPid ?? _currentProcessPid,
       _ensureParentDirectory = ensureParentDirectory ?? _defaultEnsureParentDirectory,
       _openLockFile = openLockFile ?? _defaultOpenLockFile,
       _aclBootstrap = aclBootstrap ?? GlobalStorageAclBootstrap(),
       _metadataReader = metadataReader ?? const SchedulerLockMetadataReader(),
       _processLifetimeChecker = processLifetimeChecker ?? WindowsProcessLifetimeChecker(),
       _staleLockRecovery =
           staleLockRecovery ??
           SchedulerStaleLockRecovery(
             metadataReader: metadataReader,
             processLifetimeChecker: processLifetimeChecker,
             aclBootstrap: aclBootstrap,
             currentPid: currentPid,
           ),
       _failureResolver = failureResolver ?? SchedulerLockFailureResolver(metadataReader: metadataReader);

  static const int _windowsAccessDeniedErrorCode = 5;
  static const int _posixAccessDeniedErrorCode = 13;

  static final Set<String> _heldLockFilePaths = <String>{};

  static int _currentProcessPid() => pid;
  static Future<void> _defaultEnsureParentDirectory(Directory directory) async {
    await directory.create(recursive: true);
  }

  static Future<RandomAccessFile> _defaultOpenLockFile(File file) async {
    return file.open(mode: FileMode.write);
  }

  final String _lockFilePath;
  final String _appDirectoryPath;
  final AgentRuntimeIdentity? _runtimeIdentity;
  final int Function() _currentPid;
  final SchedulerLockDirectoryEnsurer _ensureParentDirectory;
  final SchedulerLockFileOpener _openLockFile;
  final GlobalStorageAclBootstrap _aclBootstrap;
  final SchedulerLockMetadataReader _metadataReader;
  final WindowsProcessLifetimeChecker _processLifetimeChecker;
  final SchedulerStaleLockRecovery _staleLockRecovery;
  final SchedulerLockFailureResolver _failureResolver;

  RandomAccessFile? _handle;

  @override
  bool get isHeld => _handle != null;

  String get lockFilePath => _lockFilePath;

  @override
  Future<Result<Unit>> tryAcquire() => _tryAcquireOnce();

  Future<Result<Unit>> _tryAcquireOnce({bool isRetry = false}) async {
    if (_handle != null) {
      return const Success(unit);
    }

    final file = File(_lockFilePath);
    RandomAccessFile? handle;
    try {
      await _ensureParentDirectory(file.parent);
      if (_heldLockFilePaths.contains(_lockFilePath)) {
        return Failure(
          await _resolveFailure(
            const FileSystemException('Scheduler lock is already held in-process.'),
            lockHolderAlive: true,
          ),
        );
      }

      handle = await _openLockFile(file);
      await handle.lock();
      final identity = _runtimeIdentity;
      final payload = StringBuffer()
        ..writeln('pid=${_currentPid()}')
        ..writeln('acquired_at=${DateTime.now().toUtc().toIso8601String()}');
      if (identity != null) {
        payload.writeln('runtime_instance_id=${identity.runtimeInstanceId}');
        payload.writeln('runtime_session_id=${identity.runtimeSessionId}');
      }
      await handle.setPosition(0);
      await handle.writeString(payload.toString());
      await handle.flush();
      _handle = handle;
      _heldLockFilePaths.add(_lockFilePath);
      await _aclBootstrap.normalizeLockFile(_lockFilePath);
      return const Success(unit);
    } on FileSystemException catch (error) {
      await _closeQuietly(handle);
      if (!isRetry && _isAccessDenied(error)) {
        final lockHolderAlive = await _isForeignLockHolderAlive();
        if (lockHolderAlive) {
          return Failure(await _resolveFailure(error, lockHolderAlive: true));
        }
        if (await _staleLockRecovery.tryRemoveStaleLock(
          lockFilePath: _lockFilePath,
          appDirectoryPath: _appDirectoryPath,
        )) {
          return _tryAcquireOnce(isRetry: true);
        }
      }
      return Failure(
        await _resolveFailure(
          error,
          lockHolderAlive: await _isForeignLockHolderAlive(),
        ),
      );
    }
  }

  Future<bool> _isForeignLockHolderAlive() async {
    final metadata = await _metadataReader.read(_lockFilePath);
    final lockPid = metadata?.pid;
    if (lockPid == null || lockPid == _currentPid()) {
      return false;
    }
    return _processLifetimeChecker.isProcessRunning(lockPid);
  }

  Future<ActionAuthorizationFailure> _resolveFailure(
    FileSystemException error, {
    required bool lockHolderAlive,
  }) async {
    final metadata = await _metadataReader.read(_lockFilePath);
    return _failureResolver.resolve(
      error,
      lockFilePath: _lockFilePath,
      metadata: metadata,
      lockHolderAlive: lockHolderAlive,
    );
  }

  bool _isAccessDenied(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == _windowsAccessDeniedErrorCode || code == _posixAccessDeniedErrorCode) {
      return true;
    }

    final message = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    return message.contains('access is denied') ||
        message.contains('permission denied') ||
        message.contains('acesso negado') ||
        message.contains('permissao negada');
  }

  @override
  Future<void> release() async {
    final handle = _handle;
    _handle = null;
    if (handle == null) {
      return;
    }
    _heldLockFilePaths.remove(_lockFilePath);

    try {
      await handle.unlock();
      await handle.close();
    } on FileSystemException {
      // Best-effort release during shutdown.
    }

    try {
      File(_lockFilePath).deleteSync();
    } on FileSystemException {
      // Lock file may already be gone after crash recovery.
    }
  }

  Future<void> _closeQuietly(RandomAccessFile? handle) async {
    if (handle == null) {
      return;
    }

    try {
      await handle.close();
    } on FileSystemException {
      // Best-effort cleanup after a failed acquisition.
    }
  }
}
