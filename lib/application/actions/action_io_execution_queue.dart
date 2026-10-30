import 'package:plug_agente/application/actions/action_execution_queue.dart';
import 'package:plug_agente/application/actions/action_io_session_supervisor.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_control.dart';
import 'package:result_dart/result_dart.dart';

/// Schedules already admitted sessions in the same queue as legacy actions.
/// The factory reauthorizes and commits starting state before creating a process.
final class ActionIoExecutionQueue {
  ActionIoExecutionQueue(this._queue, this._supervisor, {IActionIoMetrics? metrics}) : _metrics = metrics;
  final ActionExecutionQueue _queue;
  final ActionIoSessionSupervisor _supervisor;
  final IActionIoMetrics? _metrics;
  int _waiting = 0;

  Result<Unit> cancelPending(String executionId) {
    final result = _queue.cancelQueued(executionId: executionId);
    final failure = result.exceptionOrNull();
    if (failure != null && !(failure is ActionFailure && failure.code == AgentActionFailureCode.queueItemNotFound)) {
      return Failure(failure);
    }
    return const Success(unit);
  }

  Future<Result<Unit>> enqueue({
    required String actionId,
    required String executionId,
    required AgentActionDefinitionPolicies policies,
    required Future<Result<IActionIoSessionControl>> Function() create,
    Future<Result<Unit>> Function()? prepare,
  }) async {
    var waiting = true;
    _waiting++;
    _metrics?.setQueueWaiting(_waiting);
    void releaseWaiting() {
      if (!waiting) return;
      waiting = false;
      _waiting--;
      _metrics?.setQueueWaiting(_waiting);
    }

    try {
      return await _queue.enqueue(
        AgentActionQueueRequest<Unit>(
          actionId: actionId,
          executionId: executionId,
          policies: policies,
          // Client-scoped deduplication belongs exclusively to the durable journal.
          // Never enter the legacy action/key response cache.
          task: () async {
            releaseWaiting();
            var creationAttempted = false;
            try {
              if (prepare != null) {
                final ready = await prepare();
                if (ready.isError()) return ready;
              }
              final started = await _supervisor.start(executionId, () {
                creationAttempted = true;
                return create();
              });
              if (started.isError()) {
                if (creationAttempted) _queue.retainUnconfirmedExecution(executionId);
                return Failure(started.exceptionOrNull()!);
              }
              final cleanup = await started.getOrThrow().runAndDrain();
              if (cleanup.isError()) _queue.retainUnconfirmedExecution(executionId);
              return cleanup;
            } on Object catch (error) {
              if (creationAttempted) _queue.retainUnconfirmedExecution(executionId);
              return Failure(
                ActionRuntimeFailure.withContext(
                  message: creationAttempted
                      ? 'Native session cleanup could not be confirmed.'
                      : 'Session preparation failed.',
                  code: creationAttempted ? 'ACTION_IO_CLEANUP_UNKNOWN' : 'ACTION_IO_PREPARATION_FAILED',
                  cause: error,
                ),
              );
            }
          },
        ),
      );
    } finally {
      releaseWaiting();
    }
  }
}
