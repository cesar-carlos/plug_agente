import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

abstract class IAgentActionRepository {
  Future<Result<AgentActionDefinition>> saveDefinition(
    AgentActionDefinition definition,
  );

  Future<Result<AgentActionDefinition>> getDefinition(String id);

  Future<Result<List<AgentActionDefinition>>> listDefinitions();

  Future<Result<void>> deleteDefinition(String id);

  Future<Result<AgentActionTrigger>> saveTrigger(
    AgentActionTrigger trigger,
  );

  Future<Result<AgentActionTrigger>> getTrigger(String id);

  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  });

  Future<Result<void>> deleteTrigger(String id);

  Future<Result<AgentActionExecution>> saveExecution(
    AgentActionExecution execution,
  );

  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  });

  /// Reads a UTF-8 window from spilled stdout/stderr chunks without loading the full stream.
  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  });

  /// Lists executions ordered by `requestedAt` descending.
  ///
  /// When [limit] is omitted, a conservative default cap applies. Pass `limit <= 0`
  /// to request no cap.
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  });

  Future<Result<int>> cleanupExecutions({
    required DateTime olderThan,
  });

  /// Clears stored stdout/stderr on terminal executions older than [olderThan].
  ///
  /// Does not delete execution rows or touch `queued` / `running` executions.
  Future<Result<int>> clearCapturedOutputOlderThan({
    required DateTime olderThan,
  });
}
