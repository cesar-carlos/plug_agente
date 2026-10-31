import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_execution_status.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

/// Projects journal metadata for existing history and RPC consumers. Output
/// remains exclusively in the binary journal, never in legacy text fields.
abstract final class ActionIoExecutionProjection {
  static Result<AgentActionExecution> fromSnapshot(ActionIoExecutionSnapshot snapshot) {
    final identity = snapshot.session;
    final type = AgentActionType.values.where((type) => type.name == identity.actionType).firstOrNull;
    if (type == null ||
        !const {'queued', 'starting', 'running', 'finished', 'unknown'}.contains(snapshot.processState)) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The original execution metadata is unavailable.',
          code: 'ACTION_IO_SNAPSHOT_UNAVAILABLE',
        ),
      );
    }
    final failure = snapshot.failureCode;
    final status = switch (snapshot.processState) {
      'queued' => AgentActionExecutionStatus.queued,
      'starting' || 'running' => AgentActionExecutionStatus.running,
      'unknown' => AgentActionExecutionStatus.unknown,
      _ when failure == 'ACTION_CANCELLED' => AgentActionExecutionStatus.cancelled,
      _ when failure == 'ACTION_TIMEOUT' => AgentActionExecutionStatus.timedOut,
      _ when failure != null || snapshot.captureState != 'complete' => AgentActionExecutionStatus.failed,
      _ when snapshot.exitCode == null => AgentActionExecutionStatus.unknown,
      _ => AgentActionExecutionStatus.succeeded,
    };
    return Success(
      AgentActionExecution(
        id: identity.executionId,
        actionId: identity.actionId,
        actionType: type,
        status: status,
        requestedAt: snapshot.createdAt,
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: snapshot.idempotencyKey,
        runtimeInstanceId: identity.installationId,
        triggerId: identity.triggerId,
        triggerType: AgentActionTriggerType.remote,
        definitionSnapshotHash: identity.definitionHash,
        finishedAt: snapshot.terminalAt,
        exitCode: snapshot.exitCode,
        failureCode: failure,
        ioStatus: ActionIoExecutionStatus(
          processState: snapshot.processState,
          stdinState: snapshot.stdinState,
          captureState: snapshot.captureState,
          outputExpired: snapshot.outputExpired,
          admittedInputBytes: snapshot.admittedInputBytes,
          confirmedInputBytes: snapshot.confirmedInputBytes,
          stdoutBytes: snapshot.stdoutBytes,
          stderrBytes: snapshot.stderrBytes,
        ),
      ),
    );
  }
}
