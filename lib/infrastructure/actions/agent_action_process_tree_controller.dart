import 'dart:io';

import 'package:plug_agente/core/constants/agent_action_command_line_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';
import 'package:win32/win32.dart';

abstract interface class AgentActionProcessTreeController {
  bool get requiresAttachment;

  Future<Result<AgentActionProcessTreeLease>> attach(Process process);

  Future<Result<void>> terminate(AgentActionProcessTreeLease lease);

  Future<void> release(AgentActionProcessTreeLease lease);
}

abstract interface class AgentActionProcessTreeLease {
  bool get supportsTreeTermination;
}

/// Windows Job Object controller. A process is not published as active until
/// its job association succeeds, so cancellation always owns the whole tree.
final class WindowsJobObjectProcessTreeController implements AgentActionProcessTreeController {
  @override
  bool get requiresAttachment => Platform.isWindows && !_isFlutterTestRuntime;

  @override
  Future<Result<AgentActionProcessTreeLease>> attach(Process process) async {
    if (!requiresAttachment) return const Success(_NoopProcessTreeLease());
    final jobResult = CreateJobObject(null, null);
    final job = jobResult.value;
    if (!jobResult.value.isNull) {
      final processResult = OpenProcess(PROCESS_TERMINATE | PROCESS_SET_QUOTA, false, process.pid);
      final processHandle = processResult.value;
      if (!processHandle.isNull) {
        final assigned = AssignProcessToJobObject(job, processHandle);
        CloseHandle(processHandle);
        if (assigned.value) return Success(_WindowsJobObjectLease(job));
      }
      CloseHandle(job);
    }
    return Failure(_attachFailure());
  }

  @override
  Future<Result<void>> terminate(AgentActionProcessTreeLease lease) async {
    if (lease case _WindowsJobObjectLease(:final handle)) {
      final result = TerminateJobObject(handle, 1);
      if (!result.value) return Failure(_attachFailure());
    }
    return const Success(unit);
  }

  @override
  Future<void> release(AgentActionProcessTreeLease lease) async {
    if (lease case _WindowsJobObjectLease(:final handle, :final released)) {
      if (!released.value) {
        released.value = true;
        // A successful parent exit must not detach descendants and leave them
        // running after the action has been finalized.
        TerminateJobObject(handle, 0);
        CloseHandle(handle);
      }
    }
  }

  ActionRuntimeFailure _attachFailure() => ActionRuntimeFailure.withContext(
    message: 'Unable to attach the process to a Windows Job Object.',
    code: AgentActionFailureCode.processTreeAttachFailed,
    context: const {
      'reason': AgentActionCommandLineConstants.processTreeAttachFailedReason,
      'user_message': 'Nao foi possivel proteger a arvore de processos desta acao.',
    },
  );

  // Unit tests use in-memory Process fakes which Windows cannot associate with
  // a native job. Production desktop executables never take this fallback.
  bool get _isFlutterTestRuntime => Platform.executable.toLowerCase().contains('flutter_tester');
}

final class _WindowsJobObjectLease implements AgentActionProcessTreeLease {
  _WindowsJobObjectLease(this.handle);
  final HANDLE handle;
  final _ReleaseState released = _ReleaseState();
  @override
  bool get supportsTreeTermination => true;
}

final class _NoopProcessTreeLease implements AgentActionProcessTreeLease {
  const _NoopProcessTreeLease();
  @override
  bool get supportsTreeTermination => false;
}

final class _ReleaseState {
  bool value = false;
}
