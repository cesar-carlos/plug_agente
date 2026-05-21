import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentActionTrigger {
  SaveAgentActionTrigger(
    this._repository,
    this._validateTrigger,
    this._featureFlags,
  );

  final IAgentActionRepository _repository;
  final ValidateAgentActionTrigger _validateTrigger;
  final FeatureFlags _featureFlags;

  Future<Result<AgentActionTrigger>> call(
    AgentActionTrigger trigger,
  ) async {
    if (_featureFlags.enableAgentActionsMaintenanceMode) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action triggers cannot be saved while maintenance mode is enabled.',
          code: AgentActionFailureCode.maintenanceMode,
          context: const {
            'reason': AgentActionGateConstants.maintenanceModeReason,
            'user_message':
                'Gatilhos ficam pausados no modo de manutencao. Desative a manutencao para criar ou alterar gatilhos.',
          },
        ),
      );
    }

    final validationResult = await _validateTrigger(trigger);
    if (validationResult.isError()) {
      return Failure(validationResult.exceptionOrNull()!);
    }

    final validatedTrigger = validationResult.getOrThrow();
    final persistedTrigger = validatedTrigger.copyWith(
      id: validatedTrigger.id.trim(),
      actionId: validatedTrigger.actionId.trim(),
    );

    final definitionResult = await _repository.getDefinition(persistedTrigger.actionId);
    if (definitionResult.isError()) {
      return Failure(definitionResult.exceptionOrNull()!);
    }

    final definition = definitionResult.getOrThrow();
    if (persistedTrigger.type == AgentActionTriggerType.appClose && definition.policies.remote.canRunSavedAction) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'App-close trigger cannot be saved because the action is approved for remote execution.',
          code: AgentActionFailureCode.appCloseRemoteActionBlocked,
          context: {
            'trigger_id': persistedTrigger.id,
            'action_id': persistedTrigger.actionId,
            'reason': AgentActionTriggerConstants.appCloseRemoteActionBlockedReason,
            'user_message':
                'Nao e possivel salvar um gatilho de encerramento para uma acao aprovada para execucao remota pelo hub.',
          },
        ),
      );
    }

    if (persistedTrigger.type == AgentActionTriggerType.appClose && definition.policies.elevated.runElevated) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'App-close trigger cannot be saved because the action requires elevated execution.',
          code: AgentActionFailureCode.appCloseElevatedActionBlocked,
          context: {
            'trigger_id': persistedTrigger.id,
            'action_id': persistedTrigger.actionId,
            'reason': AgentActionTriggerConstants.appCloseElevatedActionBlockedReason,
            'user_message':
                'Nao e possivel salvar um gatilho de encerramento para uma acao que exige execucao elevada (UAC).',
          },
        ),
      );
    }

    return _repository.saveTrigger(persistedTrigger);
  }
}
