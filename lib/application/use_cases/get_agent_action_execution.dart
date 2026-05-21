import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class GetAgentActionExecution {
  const GetAgentActionExecution(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<AgentActionExecution>> call(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action execution id is required.',
          context: const {
            'field': 'id',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o identificador da execucao antes de consultar.',
          },
        ),
      );
    }

    return _repository.getExecution(
      trimmed,
      hydrateCapturedOutput: hydrateCapturedOutput,
    );
  }
}
