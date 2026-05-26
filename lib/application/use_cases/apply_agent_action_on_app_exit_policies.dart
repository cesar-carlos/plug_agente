import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Applies per-action [AgentActionLifecyclePolicy.onAppExit] during controlled shutdown.
///
/// Queued executions are always cancelled before the app exits. Running executions
/// follow the action policy: kill immediately, wait briefly then kill, or leave
/// the main process running.
class ApplyAgentActionOnAppExitPolicies {
  ApplyAgentActionOnAppExitPolicies(
    this._repository,
    this._cancelExecution,
  );

  final IAgentActionRepository _repository;
  final CancelAgentActionExecution _cancelExecution;

  Future<Result<({int queuedCancelled, int runningHandled})>> call() async {
    final queuedCancelled = await _cancelQueuedExecutions();
    if (queuedCancelled.isError()) {
      return Failure(queuedCancelled.exceptionOrNull()!);
    }

    final runningHandled = await _handleRunningExecutions();
    if (runningHandled.isError()) {
      return Failure(runningHandled.exceptionOrNull()!);
    }

    return Success(
      (
        queuedCancelled: queuedCancelled.getOrThrow(),
        runningHandled: runningHandled.getOrThrow(),
      ),
    );
  }

  // Defensive cap for shutdown: limits DB load when status data is corrupted.
  // In normal operation there are at most poolSize active executions.
  static const int _shutdownActiveExecutionLimit = 200;

  Future<Result<int>> _cancelQueuedExecutions() async {
    final queuedResult = await _repository.listExecutions(
      statuses: const {AgentActionExecutionStatus.queued},
      limit: _shutdownActiveExecutionLimit,
    );
    if (queuedResult.isError()) {
      return Failure(queuedResult.exceptionOrNull()!);
    }

    var cancelled = 0;
    for (final execution in queuedResult.getOrThrow()) {
      final cancelResult = await _cancelExecution(execution.id);
      if (cancelResult.isError()) {
        return Failure(cancelResult.exceptionOrNull()!);
      }
      cancelled++;
    }

    return Success(cancelled);
  }

  Future<Result<int>> _handleRunningExecutions() async {
    final runningResult = await _repository.listExecutions(
      statuses: const {AgentActionExecutionStatus.running},
      limit: _shutdownActiveExecutionLimit,
    );
    if (runningResult.isError()) {
      return Failure(runningResult.exceptionOrNull()!);
    }

    var handled = 0;
    for (final execution in runningResult.getOrThrow()) {
      final definitionResult = await _repository.getDefinition(execution.actionId);
      if (definitionResult.isError()) {
        return Failure(definitionResult.exceptionOrNull()!);
      }

      final lifecycle = definitionResult.getOrThrow().policies.lifecycle;
      if (lifecycle.onAppExit == AgentActionOnAppExitBehavior.leaveRunning) {
        continue;
      }

      if (lifecycle.onAppExit == AgentActionOnAppExitBehavior.waitThenKillMainProcess) {
        // Cap the wait so a pathological policy value does not block exit
        // indefinitely. waitBeforeKillOnAppExit is typically a few seconds.
        const maxWait = Duration(seconds: 30);
        final wait = lifecycle.waitBeforeKillOnAppExit < maxWait
            ? lifecycle.waitBeforeKillOnAppExit
            : maxWait;
        await Future<void>.delayed(wait);
      }

      final cancelResult = await _cancelExecution(execution.id);
      if (cancelResult.isError()) {
        return Failure(cancelResult.exceptionOrNull()!);
      }
      handled++;
    }

    return Success(handled);
  }
}
