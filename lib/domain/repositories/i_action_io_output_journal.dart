import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:result_dart/result_dart.dart';

abstract interface class IActionIoOutputJournal {
  /// Atomically terminates a queued intent before it can enter starting state.
  /// False means the caller must reconcile its current process state.
  Future<Result<bool>> cancelQueued(String executionId, String clientId);

  Future<Result<ActionIoOutputEvent>> append(String executionId, ActionIoStream stream, List<int> bytes);
  Future<Result<ActionIoReadPage>> read({
    required String executionId,
    required String clientId,
    required int afterSequence,
    required int maxBytes,
  });
  Future<Result<Unit>> finish(
    String executionId, {
    required int? exitCode,
    required bool complete,
    bool processTerminated = true,
    String? failureCode,
  });
}
