import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class ListAgentActionExecutions {
  const ListAgentActionExecutions(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<List<AgentActionExecution>>> call({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    String? resolvedActionId;
    if (actionId != null) {
      final trimmed = actionId.trim();
      if (trimmed.isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Action id filter cannot be blank when listing executions.',
            context: const {
              'field': 'actionId',
              'reason': AgentActionValidationConstants.blankFilterReason,
              'user_message': 'Remova o filtro de acao ou informe um identificador valido.',
            },
          ),
        );
      }
      resolvedActionId = trimmed;
    }

    String? resolvedIdempotencyKey;
    if (idempotencyKey != null) {
      final trimmed = idempotencyKey.trim();
      if (trimmed.isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Idempotency key filter cannot be blank when listing executions.',
            context: const {
              'field': 'idempotencyKey',
              'reason': AgentActionValidationConstants.blankFilterReason,
              'user_message': 'Remova o filtro de idempotencia ou informe um valor valido.',
            },
          ),
        );
      }
      resolvedIdempotencyKey = trimmed;
    }

    return _repository.listExecutions(
      actionId: resolvedActionId,
      idempotencyKey: resolvedIdempotencyKey,
      statuses: statuses,
      requestedAfter: requestedAfter,
      limit: limit,
    );
  }
}
