import 'dart:io';

import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/windows_action_job_api.dart';
import 'package:result_dart/result_dart.dart';
import 'package:win32/win32.dart';

abstract interface class AgentActionProcessTreeController {
  bool get requiresAttachment;
  Future<Result<AgentActionProcessTreeLease>> attach(Process process);
  Future<Result<void>> terminate(AgentActionProcessTreeLease lease);
  Future<Result<void>> release(AgentActionProcessTreeLease lease);
}

abstract interface class AgentActionProcessTreeLease {
  bool get supportsTreeTermination;
}

final class WindowsJobObjectProcessTreeController implements AgentActionProcessTreeController {
  WindowsJobObjectProcessTreeController({
    WindowsActionJobApi? api,
    this.memoryLimitBytes = defaultMemoryLimitBytes,
    int cpuLimitPercent = 0,
    int Function()? cpuLimitProvider,
  }) : _cpuLimitProvider = cpuLimitProvider ?? (() => cpuLimitPercent),
       _api = api ?? WindowsActionJobApi(),
       _nativeTest = api != null;

  /// Total committed memory of one action's process tree, not working-set RAM.
  static const int defaultMemoryLimitBytes = 2 * 1024 * 1024 * 1024;
  final int memoryLimitBytes;
  final int Function() _cpuLimitProvider;
  int get cpuLimitPercent => _cpuLimitProvider();
  final WindowsActionJobApi _api;
  final bool _nativeTest;

  @override
  bool get requiresAttachment =>
      _nativeTest || (Platform.isWindows && !Platform.executable.toLowerCase().contains('flutter_tester'));

  @override
  Future<Result<AgentActionProcessTreeLease>> attach(Process process) async {
    if (!requiresAttachment) return const Success(_NoopProcessTreeLease());
    if (memoryLimitBytes <= 0) return Failure(_failure('configure_memory_limit', 0));
    if (cpuLimitPercent < 0 || cpuLimitPercent > 100) return Failure(_failure('configure_cpu_limit', 0));
    final created = _api.create();
    final job = created.value;
    if (job.isNull) return Failure(_failure('create_job', created.error.toInt()));
    final configured = _api.configure(job, memoryLimitBytes);
    if (!configured.value) {
      final closed = _api.close(job);
      return Failure(
        _failure(
          'configure_memory_limit',
          configured.error.toInt(),
          cleanupError: closed.value ? null : closed.error.toInt(),
        ),
      );
    }
    if (cpuLimitPercent > 0) {
      final cpu = _api.configureCpu(job, cpuLimitPercent);
      if (!cpu.value) {
        final closed = _api.close(job);
        return Failure(
          _failure('configure_cpu_limit', cpu.error.toInt(), cleanupError: closed.value ? null : closed.error.toInt()),
        );
      }
    }
    final opened = _api.open(process.pid);
    if (opened.value.isNull) {
      final closed = _api.close(job);
      return Failure(
        _failure('open_process', opened.error.toInt(), cleanupError: closed.value ? null : closed.error.toInt()),
      );
    }
    final assigned = _api.assign(job, opened.value);
    final processClosed = _api.close(opened.value);
    if (!assigned.value || !processClosed.value) {
      final closed = _api.close(job);
      return Failure(
        _failure(
          assigned.value ? 'close_process_handle' : 'assign_job',
          assigned.value ? processClosed.error.toInt() : assigned.error.toInt(),
          cleanupError: closed.value ? null : closed.error.toInt(),
        ),
      );
    }
    return Success(_WindowsJobObjectLease(job));
  }

  Result<Duration> readCpu(AgentActionProcessTreeLease lease) {
    if (lease is! _WindowsJobObjectLease || lease.released) return Failure(_failure('read_cpu', 0));
    final result = _api.cpuTicks(lease.handle);
    if (result.error.toInt() != 0) return Failure(_failure('read_cpu', result.error.toInt()));
    return Success(Duration(microseconds: result.value ~/ 10));
  }

  @override
  Future<Result<void>> terminate(AgentActionProcessTreeLease lease) async {
    if (lease case _WindowsJobObjectLease(:final handle)) {
      // CloseHandle permits immediate numeric-handle reuse by another job.
      // Preserve the release outcome without touching a relinquished handle.
      if (lease.released) return lease.releaseResult!;
      final result = _api.terminate(handle, 1);
      if (!result.value) return Failure(_failure('terminate_job', result.error.toInt()));
    }
    return const Success(unit);
  }

  @override
  Future<Result<void>> release(AgentActionProcessTreeLease lease) async {
    if (lease case _WindowsJobObjectLease(:final handle)) {
      if (lease.released) return lease.releaseResult!;
      final terminated = _api.terminate(handle, 0);
      // KILL_ON_JOB_CLOSE is a second line of defense even if termination fails.
      final closed = _api.close(handle);
      final Result<void> result = !terminated.value
          ? Failure(
              _failure(
                'terminate_job',
                terminated.error.toInt(),
                cleanupError: closed.value ? null : closed.error.toInt(),
              ),
            )
          : !closed.value
          ? Failure(_failure('close_job', closed.error.toInt()))
          : const Success(unit);
      lease.released = closed.value;
      lease.releaseResult = result;
      return result;
    }
    return const Success(unit);
  }

  ActionRuntimeFailure _failure(String phase, int error, {int? cleanupError}) => ActionRuntimeFailure.withContext(
    message: 'Windows action process tree operation failed.',
    code: phase == 'terminate_job' || phase == 'close_job'
        ? AgentActionFailureCode.killFailed
        : AgentActionFailureCode.processTreeAttachFailed,
    context: {
      'phase': phase,
      'reason': phase == 'terminate_job' || phase == 'close_job'
          ? 'process_tree_cleanup_failed'
          : 'process_tree_attach_failed',
      'os_error_code': error,
      'memory_limit_bytes': memoryLimitBytes,
      'cpu_limit_percent': cpuLimitPercent,
      'cleanup_os_error_code': ?cleanupError,
      'user_message': phase == 'configure_cpu_limit'
          ? 'O Windows não permitiu aplicar o limite de CPU. Revise a opção nas preferências de Ações; sessões remotas podem restringir esse controle.'
          : phase == 'terminate_job' || phase == 'close_job'
          ? 'Nao foi possivel confirmar o encerramento dos processos da acao. Verifique os processos no Gerenciador de Tarefas.'
          : 'Nao foi possivel aplicar a protecao de processos e memoria desta acao.',
    },
  );
}

final class _WindowsJobObjectLease implements AgentActionProcessTreeLease {
  _WindowsJobObjectLease(this.handle);
  final HANDLE handle;
  bool released = false;
  Result<void>? releaseResult;
  @override
  bool get supportsTreeTermination => true;
}

final class _NoopProcessTreeLease implements AgentActionProcessTreeLease {
  const _NoopProcessTreeLease();
  @override
  bool get supportsTreeTermination => false;
}
