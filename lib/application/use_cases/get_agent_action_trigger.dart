import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class GetAgentActionTrigger {
  const GetAgentActionTrigger(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<AgentActionTrigger>> call(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger id is required.',
          context: const {
            'field': 'id',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o identificador do gatilho antes de consultar.',
          },
        ),
      );
    }

    return _repository.getTrigger(trimmed);
  }
}
