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
    try {
      await file.parent.create(recursive: true);
      final handle = await file.open(mode: FileMode.write);
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
      return const Success(unit);
    } on FileSystemException catch (error) {
      return Failure(
        ActionAuthorizationFailure.withContext(
          message: 'Another Plug Agente process is already running the action scheduler.',
          code: AgentActionFailureCode.schedulerBootstrapFailed,
          cause: error,
          context: const {
            'reason': AgentActionTriggerConstants.schedulerInstanceLockedReason,
            'user_message':
                'Outro processo do Plug Agente ja esta executando o agendador de acoes nesta pasta de dados.',
          },
        ),
      );
    }
  }

  @override
  Future<void> release() async {
    final handle = _handle;
    _handle = null;
    if (handle == null) {
      return;
    }

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
}
