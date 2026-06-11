import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_lock_metadata.dart';
import 'package:plug_agente/infrastructure/actions/scheduler_lock_metadata_reader.dart';

/// Maps scheduler lock [FileSystemException]s to typed authorization failures.
class SchedulerLockFailureResolver {
  SchedulerLockFailureResolver({
    SchedulerLockMetadataReader? metadataReader,
  }) : _metadataReader = metadataReader ?? const SchedulerLockMetadataReader();

  static const int _windowsAccessDeniedErrorCode = 5;
  static const int _posixAccessDeniedErrorCode = 13;
  static const int _windowsSharingViolationErrorCode = 32;
  static const int _windowsLockViolationErrorCode = 33;

  final SchedulerLockMetadataReader _metadataReader;

  Future<ActionAuthorizationFailure> resolve(
    FileSystemException error, {
    required String lockFilePath,
    required bool lockHolderAlive,
    SchedulerLockMetadata? metadata,
  }) async {
    if (error.message.contains('already held in-process')) {
      return _lockedFailure(lockFilePath, cause: error, metadata: metadata);
    }

    if (_isLockConflict(error)) {
      return _lockedFailure(lockFilePath, cause: error, metadata: metadata);
    }

    if (_isAccessDenied(error)) {
      if (lockHolderAlive) {
        return _lockedFailure(lockFilePath, cause: error, metadata: metadata);
      }
      return _storageAccessDeniedFailure(lockFilePath, cause: error, metadata: metadata);
    }

    return _bootstrapFailure(lockFilePath, cause: error, metadata: metadata);
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

  Future<ActionAuthorizationFailure> _lockedFailure(
    String lockFilePath, {
    Object? cause,
    SchedulerLockMetadata? metadata,
  }) async {
    return ActionAuthorizationFailure.withContext(
      message: 'Another Plug Agente process is already running the action scheduler.',
      code: AgentActionFailureCode.schedulerBootstrapFailed,
      cause: cause,
      context: await _buildFailureContext(
        lockFilePath: lockFilePath,
        reason: AgentActionTriggerConstants.schedulerInstanceLockedReason,
        userMessage: 'Outro processo do Plug Agente ja esta executando o agendador de acoes nesta pasta de dados.',
        cause: cause,
        metadata: metadata,
      ),
    );
  }

  Future<ActionAuthorizationFailure> _storageAccessDeniedFailure(
    String lockFilePath, {
    Object? cause,
    SchedulerLockMetadata? metadata,
  }) async {
    return ActionAuthorizationFailure.withContext(
      message: 'Agent action scheduler lock storage is not accessible.',
      code: AgentActionFailureCode.schedulerBootstrapFailed,
      cause: cause,
      context: await _buildFailureContext(
        lockFilePath: lockFilePath,
        reason: AgentActionTriggerConstants.schedulerStorageAccessDeniedReason,
        userMessage:
            'O agendador de acoes nao conseguiu acessar o arquivo de lock em $lockFilePath. '
            'Revise permissoes de leitura/escrita nesta pasta de dados.',
        cause: cause,
        metadata: metadata,
      ),
    );
  }

  Future<ActionAuthorizationFailure> _bootstrapFailure(
    String lockFilePath, {
    Object? cause,
    SchedulerLockMetadata? metadata,
  }) async {
    return ActionAuthorizationFailure.withContext(
      message: 'Agent action scheduler lock bootstrap failed.',
      code: AgentActionFailureCode.schedulerBootstrapFailed,
      cause: cause,
      context: await _buildFailureContext(
        lockFilePath: lockFilePath,
        reason: AgentActionTriggerConstants.schedulerBootstrapFailedReason,
        userMessage:
            'O agendador de acoes falhou ao inicializar nesta pasta de dados. Reinicie o agente ou revise o estado do arquivo de lock.',
        cause: cause,
        metadata: metadata,
      ),
    );
  }

  Future<Map<String, Object?>> _buildFailureContext({
    required String lockFilePath,
    required String reason,
    required String userMessage,
    Object? cause,
    SchedulerLockMetadata? metadata,
  }) async {
    final context = <String, Object?>{
      'reason': reason,
      'user_message': userMessage,
      'lock_file_path': lockFilePath,
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
    context.addAll(
      metadata == null ? await _metadataReader.readDiagnosticsMap(lockFilePath) : _diagnosticsFromMetadata(metadata),
    );
    return context;
  }

  Map<String, Object?> _diagnosticsFromMetadata(SchedulerLockMetadata metadata) {
    return <String, Object?>{
      if (metadata.pid != null) 'lock_pid': '${metadata.pid}',
      if (metadata.acquiredAt != null) 'lock_acquired_at': metadata.acquiredAt!.toUtc().toIso8601String(),
      if (metadata.runtimeInstanceId != null) 'lock_runtime_instance_id': metadata.runtimeInstanceId,
      if (metadata.runtimeSessionId != null) 'lock_runtime_session_id': metadata.runtimeSessionId,
    };
  }
}
