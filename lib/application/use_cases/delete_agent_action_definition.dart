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

    return _repository.deleteDefinition(trimmed);
  }
}
