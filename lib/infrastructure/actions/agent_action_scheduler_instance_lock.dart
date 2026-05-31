import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/runtime/agent_runtime_identity.dart';
import 'package:plug_agente/core/storage/global_storage_path_resolver.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:result_dart/result_dart.dart';

/// File-backed exclusive lock for the agent action trigger scheduler.
class AgentActionSchedulerInstanceLock implements IAgentActionSchedulerInstanceLock {
  AgentActionSchedulerInstanceLock({
    required GlobalStorageContext storageContext,
    AgentRuntimeIdentity? runtimeIdentity,
    int Function()? currentPid,
  }) : _lockFilePath = p.join(storageContext.appDirectoryPath, _lockFileName),
       _runtimeIdentity = runtimeIdentity,
       _currentPid = currentPid ?? _currentProcessPid;

  static const String _lockFileName = 'agent_action_scheduler.lock';
  static const int _windowsAccessDeniedErrorCode = 5;
  static const int _posixAccessDeniedErrorCode = 13;
  static const int _windowsSharingViolationErrorCode = 32;
  static const int _windowsLockViolationErrorCode = 33;
  static final Set<String> _heldLockFilePaths = <String>{};

  static int _currentProcessPid() => pid;

  final String _lockFilePath;
  final AgentRuntimeIdentity? _runtimeIdentity;
  final int Function() _currentPid;

  RandomAccessFile? _handle;

  @override
  bool get isHeld => _handle != null;

  @override
  Future<Result<Unit>> tryAcquire() async {
    if (_handle != null) {
      return const Success(unit);
    }

    final file = File(_lockFilePath);
    RandomAccessFile? handle;
    try {
      await file.parent.create(recursive: true);
      if (_heldLockFilePaths.contains(_lockFilePath)) {
        return Failure(await _lockedFailure());
      }

      handle = await file.open(mode: FileMode.write);
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
      return const Success(unit);
    } on FileSystemException catch (error) {
      await _closeQuietly(handle);
      return Failure(await _classifyFileSystemFailure(error));
    }
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

  Future<ActionAuthorizationFailure> _classifyFileSystemFailure(
    FileSystemException error,
  ) async {
    if (_isLockConflict(error)) {
      return _lockedFailure(error);
    }

    if (_isAccessDenied(error)) {
      return _storageAccessDeniedFailure(error);
    }

    return _bootstrapFailure(error);
  }

  bool _isLockConflict(FileSystemException error) {
    final code = error.osError?.errorCode;
    if (code == _windowsSharingViolationErrorCode || code == _windowsLockViolationErrorCode) {
      return true;
    }

    final message = '${error.message} ${error.osError?.message ?? ''}'.toLowerCase();
    return message.contains('sharing violation') ||
        message.contains('lock violation') ||
        message.contains('has locked a portion of the file') ||
        message.contains('cannot access the file because it is being used by another process');
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

  Future<ActionAuthorizationFailure> _lockedFailure([Object? cause]) async {
    return ActionAuthorizationFailure.withContext(
      message: 'Another Plug Agente process is already running the action scheduler.',
      code: AgentActionFailureCode.schedulerBootstrapFailed,
      cause: cause,
      context: await _buildFailureContext(
        reason: AgentActionTriggerConstants.schedulerInstanceLockedReason,
        userMessage: 'Outro processo do Plug Agente ja esta executando o agendador de acoes nesta pasta de dados.',
        cause: cause,
      ),
    );
  }

  Future<ActionAuthorizationFailure> _storageAccessDeniedFailure([Object? cause]) async {
    return ActionAuthorizationFailure.withContext(
      message: 'Agent action scheduler lock storage is not accessible.',
      code: AgentActionFailureCode.schedulerBootstrapFailed,
      cause: cause,
      context: await _buildFailureContext(
        reason: AgentActionTriggerConstants.schedulerStorageAccessDeniedReason,
        userMessage:
            'O agendador de acoes nao conseguiu acessar o arquivo de lock nesta pasta de dados. Revise permissoes de leitura/escrita ou execute o agente com privilegios adequados.',
        cause: cause,
      ),
    );
  }

  Future<ActionAuthorizationFailure> _bootstrapFailure([Object? cause]) async {
    return ActionAuthorizationFailure.withContext(
      message: 'Agent action scheduler lock bootstrap failed.',
      code: AgentActionFailureCode.schedulerBootstrapFailed,
      cause: cause,
      context: await _buildFailureContext(
        reason: AgentActionTriggerConstants.schedulerBootstrapFailedReason,
        userMessage:
            'O agendador de acoes falhou ao inicializar nesta pasta de dados. Reinicie o agente ou revise o estado do arquivo de lock.',
        cause: cause,
      ),
    );
  }

  Future<Map<String, Object?>> _buildFailureContext({
    required String reason,
    required String userMessage,
    Object? cause,
  }) async {
    final context = <String, Object?>{
      'reason': reason,
      'user_message': userMessage,
      'lock_file_path': _lockFilePath,
    };
    if (cause is FileSystemException) {
      final osError = cause.osError;
      if (osError != null) {
        context['os_error_code'] = osError.errorCode;
        if (osError.message.isNotEmpty) {
          context['os_error_message'] = osError.message;
        }
      }
      if (cause.path case final String path when path.trim().isNotEmpty) {
        context['os_error_path'] = path.trim();
      }
    }
    context.addAll(await _readLockFileMetadata());
    return context;
  }

  Future<Map<String, Object?>> _readLockFileMetadata() async {
    final file = File(_lockFilePath);
    if (!file.existsSync()) {
      return const <String, Object?>{};
    }

    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty) {
        return const <String, Object?>{};
      }
      final metadata = <String, Object?>{};
      for (final line in lines) {
        final separatorIndex = line.indexOf('=');
        if (separatorIndex <= 0 || separatorIndex >= line.length - 1) {
          continue;
        }
        final key = line.substring(0, separatorIndex).trim();
        final value = line.substring(separatorIndex + 1).trim();
        if (key.isEmpty || value.isEmpty) {
          continue;
        }
        metadata['lock_$key'] = value;
      }
      return metadata;
    } on FileSystemException {
      return const <String, Object?>{};
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
