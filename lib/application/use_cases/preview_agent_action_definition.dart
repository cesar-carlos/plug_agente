import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class PreviewAgentActionDefinition {
  const PreviewAgentActionDefinition(
    this._repository,
    this._adapterRegistry,
  );

  final IAgentActionRepository _repository;
  final AgentActionAdapterRegistry _adapterRegistry;

  Future<Result<AgentActionPreparedExecution>> call(
    String actionId, {
    AgentActionRequestSource source = AgentActionRequestSource.localUi,
  }) async {
    final trimmedActionId = actionId.trim();
    if (trimmedActionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required to preview an action definition.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe a acao que sera usada para gerar o preview.',
          },
        ),
      );
    }

    final definitionResult = await _repository.getDefinition(trimmedActionId);
    if (definitionResult.isError()) {
      return Failure(definitionResult.exceptionOrNull()!);
    }
    final definition = definitionResult.getOrThrow();

    final adapterResult = _adapterRegistry.resolve(definition.type);
    if (adapterResult.isError()) {
      return Failure(adapterResult.exceptionOrNull()!);
    }

    return adapterResult.getOrThrow().prepareExecution(
      definition: definition,
      request: AgentActionExecutionRequest(
        actionId: definition.id,
        source: source,
      ),
    );
  }
}
