import 'package:plug_agente/application/use_cases/save_agent_action_execution.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Fills missing [AgentActionExecution.traceId] / [AgentActionExecution.requestedBy]
/// from a later Hub RPC (e.g. cancel or getExecution) without overwriting existing values.
class BackfillAgentActionExecutionCorrelation {
  BackfillAgentActionExecutionCorrelation(
    IAgentActionRepository repository, {
    SaveAgentActionExecution? saveExecution,
  }) : _saveExecution = saveExecution ?? SaveAgentActionExecution(repository);

  final SaveAgentActionExecution _saveExecution;

  Future<Result<AgentActionExecution>> call({
    required AgentActionExecution execution,
    String? traceId,
    String? requestedBy,
  }) async {
    final patchTrace = _trimOrNull(traceId);
    final patchRequestedBy = _trimOrNull(requestedBy);
    final hasTrace = _trimOrNull(execution.traceId) != null;
    final hasRequestedBy = _trimOrNull(execution.requestedBy) != null;

    if ((patchTrace == null || hasTrace) && (patchRequestedBy == null || hasRequestedBy)) {
      return Success(execution);
    }

    final updated = execution.copyWith(
      traceId: hasTrace ? execution.traceId : patchTrace,
      requestedBy: hasRequestedBy ? execution.requestedBy : patchRequestedBy,
    );
    return _saveExecution(updated);
  }

  String? _trimOrNull(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
