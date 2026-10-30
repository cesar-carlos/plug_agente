import 'package:plug_agente/application/actions/action_io_execution_projection.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:result_dart/result_dart.dart';

/// Operator-only cancellation. Remote callers must use ActionIoRemoteAccess.
final class ActionIoLocalCancellation {
  const ActionIoLocalCancellation({
    required IActionIoSessionLookup sessions,
    required IActionIoOutputJournal output,
    required Result<bool> Function(String) requestCancel,
  }) : _sessions = sessions,
       _output = output,
       _requestCancel = requestCancel;

  final IActionIoSessionLookup _sessions;
  final IActionIoOutputJournal _output;
  final Result<bool> Function(String) _requestCancel;

  Future<Result<AgentActionExecution>> call({
    required String executionId,
    required Future<Result<Unit>> Function() authorize,
  }) async {
    try {
      (await authorize()).getOrThrow();
      final snapshot = (await _sessions.getExecutionSnapshot(executionId)).getOrThrow();
      if (snapshot.processState != 'finished' && snapshot.processState != 'unknown') {
        (await authorize()).getOrThrow();
        final queued = (await _output.cancelQueued(executionId, snapshot.session.clientId)).getOrThrow();
        if (!queued) {
          final current = (await _sessions.getExecutionSnapshot(executionId)).getOrThrow();
          if (current.processState != 'finished' && current.processState != 'unknown') {
            (await authorize()).getOrThrow();
            if (!_requestCancel(executionId).getOrThrow()) {
              return Failure(
                ActionRuntimeFailure.withContext(
                  message: 'The running process could not be confirmed. Cancellation was not confirmed.',
                  code: 'ACTION_OUTCOME_UNKNOWN',
                ),
              );
            }
          }
        }
      }
      final current = (await _sessions.getExecutionSnapshot(executionId)).getOrThrow();
      (await authorize()).getOrThrow();
      return ActionIoExecutionProjection.fromSnapshot(current);
    } on ActionFailure catch (failure) {
      return Failure(failure);
    } on Object catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Cancellation could not be confirmed. Refresh the execution status.',
          code: 'ACTION_IO_CANCEL_FAILED',
          cause: error,
        ),
      );
    }
  }
}
