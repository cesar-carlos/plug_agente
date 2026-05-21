import 'package:plug_agente/application/use_cases/validate_agent_action_definition.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class TestAgentActionDefinition {
  const TestAgentActionDefinition(
    this._repository,
    this._validateDefinition,
  );

  final IAgentActionRepository _repository;
  final ValidateAgentActionDefinition _validateDefinition;

  Future<Result<AgentActionPreflight>> call(String actionId) async {
    final trimmedActionId = actionId.trim();
    if (trimmedActionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required to test an action definition.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe a acao que sera testada.',
          },
        ),
      );
    }

    final definitionResult = await _repository.getDefinition(trimmedActionId);
    if (definitionResult.isError()) {
      return Failure(definitionResult.exceptionOrNull()!);
    }

    return _validateDefinition(definitionResult.getOrThrow());
  }
}
