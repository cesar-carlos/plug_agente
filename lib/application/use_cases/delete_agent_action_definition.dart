import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class DeleteAgentActionDefinition {
  const DeleteAgentActionDefinition(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<void>> call(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action definition id is required for delete.',
          context: const {
            'field': 'id',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o identificador da acao antes de excluir.',
          },
        ),
      );
    }

    final triggers = await _repository.listTriggers(
      isEnabled: true,
      types: const {AgentActionTriggerType.actionSucceeded, AgentActionTriggerType.actionFailed},
    );
    if (triggers.isError()) return Failure(triggers.exceptionOrNull()!);
    if (triggers.getOrThrow().any((trigger) => trigger.schedule.sourceActionId?.trim() == trimmed)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action is referenced by enabled execution event triggers.',
          context: const {
            'reason': 'action_has_event_dependents',
            'user_message': 'Desative ou exclua os gatilhos que dependem desta acao antes de exclui-la.',
          },
        ),
      );
    }
    return _repository.deleteDefinition(trimmed);
  }
}
