import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentActionExecution {
  const SaveAgentActionExecution(IAgentActionRepository repository) : _repository = repository;

  final IAgentActionRepository _repository;

  Future<Result<AgentActionExecution>> call(
    AgentActionExecution execution,
  ) async {
    if (execution.id.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Execution id is required to save an action execution.',
          context: const {
            'field': 'id',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o identificador da execucao antes de salvar.',
          },
        ),
      );
    }

    if (execution.actionId.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required to save an action execution.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe a acao vinculada a esta execucao antes de salvar.',
          },
        ),
      );
    }

    final idempotencyKey = execution.idempotencyKey;
    if (idempotencyKey != null && idempotencyKey.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Idempotency key cannot be blank when set on an action execution.',
          context: const {
            'field': 'idempotencyKey',
            'reason': AgentActionValidationConstants.blankValueReason,
            'user_message': 'Remova a chave de idempotencia ou informe um valor valido.',
          },
        ),
      );
    }

    return _repository.saveExecution(execution);
  }
}
