import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionTriggerDefinitionValidator {
  const AgentActionTriggerDefinitionValidator();

  Result<void> validate(AgentActionTrigger trigger, AgentActionDefinition definition) {
    if (!definition.type.supportsTrigger(trigger.type)) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action type does not support this trigger.',
          code: AgentActionFailureCode.commandLineLocalOnly,
          context: const {
            'reason': 'command_line_local_only',
            'user_message':
                'Linha de comando aceita apenas gatilho manual local. Use Executavel ou Script para automatizar.',
          },
        ),
      );
    }
    if (trigger.type != AgentActionTriggerType.appClose) return const Success(unit);
    if (definition.policies.remote.canRunSavedAction) {
      return _failure(
        AgentActionFailureCode.appCloseRemoteActionBlocked,
        AgentActionTriggerConstants.appCloseRemoteActionBlockedReason,
        'Nao e possivel usar gatilho de fechamento em uma acao aprovada para execucao remota.',
      );
    }
    if (definition.policies.elevated.runElevated) {
      return _failure(
        AgentActionFailureCode.appCloseElevatedActionBlocked,
        AgentActionTriggerConstants.appCloseElevatedActionBlockedReason,
        'Gatilhos de fechamento nao permitem execucao elevada (UAC).',
      );
    }
    if (definition.policies.timeout.maxRuntime > AgentActionTriggerConstants.appCloseExecutionBudget) {
      return _failure(
        AgentActionFailureCode.appCloseRuntimeTooLong,
        AgentActionTriggerConstants.appCloseRuntimeTooLongReason,
        'Para executar ao fechar o agente, configure o tempo maximo em ate 5 segundos.',
      );
    }
    if (!definition.type.supportsProcessTermination ||
        !definition.policies.timeout.killMainProcessOnTimeout ||
        definition.policies.retry.maxAttempts > 1) {
      return _failure(
        AgentActionFailureCode.appCloseRuntimeTooLong,
        'app_close_requires_bounded_process',
        'O fechamento exige uma acao com processo, encerramento no timeout e uma unica tentativa.',
      );
    }
    return const Success(unit);
  }

  Result<void> _failure(String code, String reason, String message) => Failure(
    ActionValidationFailure.withContext(
      message: 'Action is incompatible with app-close execution.',
      code: code,
      context: {'reason': reason, 'user_message': message},
    ),
  );
}
