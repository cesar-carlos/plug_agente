import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:plug_agente/domain/repositories/i_action_io_process.dart';
import 'package:plug_agente/infrastructure/actions/action_io_process_input_pipe.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_process_tree_controller.dart';
import 'package:plug_agente/infrastructure/actions/windows_silent_action_process.dart';
import 'package:result_dart/result_dart.dart';

/// Only accepts an invocation resolved locally from an approved saved action.
/// The caller commits starting state and reauthorizes before invoking [start].
final class WindowsActionIoProcess implements IActionIoProcess {
  WindowsActionIoProcess._(this._process, this._controller, this._lease)
    : input = ActionIoProcessInputPipe(_process.stdin) {
    exitCode = _observeExit();
  }

  final WindowsSilentActionProcess _process;
  final AgentActionProcessTreeController _controller;
  final AgentActionProcessTreeLease _lease;
  Future<Result<Unit>>? _termination;
  Future<Result<Unit>>? _closing;
  bool _resumed = false;
  bool _exited = false;

  static Future<Result<WindowsActionIoProcess>> start({
    required String executable,
    required List<String> arguments,
    required AgentActionProcessTreeController controller,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) async {
    if (!controller.requiresAttachment) return Failure(_failure('ACTION_IO_PROTECTION_REQUIRED'));
    WindowsSilentActionProcess? process;
    AgentActionProcessTreeLease? lease;
    try {
      process =
          await WindowsSilentActionProcess.start(
                executable,
                arguments,
                workingDirectory: workingDirectory,
                environment: environment,
                includeParentEnvironment: includeParentEnvironment,
                startSuspended: true,
                requiresStdin: true,
                faithfulOutput: true,
              )
              as WindowsSilentActionProcess;
      lease = (await controller.attach(process)).getOrThrow();
      if (!lease.supportsTreeTermination) throw _failure('ACTION_IO_PROTECTION_REQUIRED');
      return Success(WindowsActionIoProcess._(process, controller, lease));
    } on Object catch (error) {
      final cleanup = <String>[];
      if (process != null) {
        if (lease != null) {
          try {
            final released = await controller.release(lease);
            if (released.isError()) cleanup.add('job_release');
          } on Object {
            cleanup.add('job_release');
          }
        }
        // The primary thread is still suspended; cleanup retains the native
        // process until exit rather than treating a logical timeout as disposal.
        process.kill();
        try {
          await process.exitCode;
        } on Object {
          cleanup.add('exit_observation');
        }
        try {
          await process.closeCapturedOutput();
        } on Object {
          cleanup.add('output_cleanup');
        }
      }
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The protected I/O process could not be started.',
          code: error is ActionFailure ? error.code : 'ACTION_IO_PROCESS_START_FAILED',
          context: {
            'retryable': false,
            'cause_type': error.runtimeType.toString(),
            if (cleanup.isNotEmpty) 'secondary_failures': cleanup,
          },
        ),
      );
    }
  }

  @override
  final IActionIoInputPipe input;
  @override
  late final Future<Result<int>> exitCode;
  @override
  int get pid => _process.pid;
  @override
  Stream<List<int>> get stdout => _process.stdout;
  @override
  Stream<List<int>> get stderr => _process.stderr;

  Future<Result<int>> _observeExit() async {
    try {
      return Success(await _process.exitCode);
    } on Object {
      return Failure(_failure('ACTION_OUTCOME_UNKNOWN'));
    } finally {
      _exited = true;
    }
  }

  @override
  Result<Unit> resume() {
    if (_exited || _termination != null || _closing != null) return Failure(_failure('ACTION_IO_PROCESS_CLOSED'));
    if (_resumed) return const Success(unit);
    try {
      _process.resume();
      _resumed = true;
      return const Success(unit);
    } on Object {
      return Failure(_failure('ACTION_IO_PROCESS_RESUME_FAILED'));
    }
  }

  @override
  Future<Result<Unit>> terminate() => _termination ??= _terminate();

  Future<Result<Unit>> _terminate() async {
    try {
      final result = await _controller.terminate(_lease);
      if (result.isError()) return Failure(result.exceptionOrNull()!);
      return const Success(unit);
    } on Object {
      return Failure(_failure('ACTION_IO_PROCESS_TERMINATION_FAILED'));
    }
  }

  @override
  Future<Result<Unit>> close() => _closing ??= _close();

  Future<Result<Unit>> _close() async {
    // Job release terminates descendants and supplies KILL_ON_JOB_CLOSE fallback.
    Exception? failure;
    final secondary = <String>[];
    try {
      final released = await _controller.release(_lease);
      failure = released.exceptionOrNull();
    } on Object {
      failure = _failure('ACTION_IO_PROCESS_TERMINATION_FAILED');
    }
    final exited = await exitCode;
    if (exited.isError()) {
      if (failure == null) {
        failure = exited.exceptionOrNull();
      } else {
        secondary.add('exit_observation');
      }
    }
    try {
      await _process.closeCapturedOutput();
    } on Object {
      if (failure == null) {
        failure = _failure('ACTION_IO_CLEANUP_FAILED');
      } else {
        secondary.add('output_cleanup');
      }
    }
    if (failure != null) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The protected I/O process cleanup could not be confirmed.',
          code: failure is ActionFailure ? failure.code : 'ACTION_IO_CLEANUP_FAILED',
          context: {'retryable': false, if (secondary.isNotEmpty) 'secondary_failures': secondary},
        ),
      );
    }
    return const Success(unit);
  }

  static ActionRuntimeFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'The protected I/O process operation could not be confirmed.',
    code: code,
    context: const {'retryable': false},
  );
}
