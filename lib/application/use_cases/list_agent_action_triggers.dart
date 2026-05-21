import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class ListAgentActionTriggers {
  const ListAgentActionTriggers(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<List<AgentActionTrigger>>> call({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async {
    String? resolvedActionId;
    if (actionId != null) {
      final trimmed = actionId.trim();
      if (trimmed.isEmpty) {
        return Failure(
          ActionValidationFailure.withContext(
            message: 'Action id filter cannot be blank when listing triggers.',
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

    return _repository.listTriggers(
      actionId: resolvedActionId,
      isEnabled: isEnabled,
      types: types,
    );
  }
}
