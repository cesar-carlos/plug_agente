import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/core/constants/agent_action_rpc_constants.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

/// Runs a saved action for Hub JSON-RPC by dispatching an enabled `remote` trigger.
class RunAgentActionViaRemoteTrigger {
  RunAgentActionViaRemoteTrigger(
    this._repository,
    this._dispatchTrigger,
  );

  final IAgentActionRepository _repository;
  final DispatchAgentActionTrigger _dispatchTrigger;

  Future<Result<AgentActionExecution>> call({
    required String actionId,
    required String idempotencyKey,
    String? triggerId,
    String? requestedBy,
    String? traceId,
  }) async {
    final trimmedActionId = actionId.trim();
    if (trimmedActionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required for remote trigger dispatch.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe a acao que sera executada remotamente.',
          },
        ),
      );
    }

    final trimmedIdempotencyKey = idempotencyKey.trim();
    if (trimmedIdempotencyKey.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote agent action run requires an idempotency key.',
          code: AgentActionFailureCode.remoteIdempotencyRequired,
          context: const {
            'field': 'idempotencyKey',
            'reason': AgentActionRpcConstants.remoteIdempotencyRequiredRpcReason,
            'user_message': 'Informe uma chave de idempotencia para a execucao remota.',
          },
        ),
      );
    }

    final resolvedTriggerResult = await _resolveRemoteTriggerId(
      actionId: trimmedActionId,
      triggerId: triggerId,
    );
    if (resolvedTriggerResult.isError()) {
      return Failure(resolvedTriggerResult.exceptionOrNull()!);
    }

    return _dispatchTrigger(
      triggerId: resolvedTriggerResult.getOrThrow(),
      idempotencyKey: trimmedIdempotencyKey,
      requestedBy: requestedBy?.trim(),
      traceId: traceId?.trim(),
    );
  }

  Future<Result<String>> _resolveRemoteTriggerId({
    required String actionId,
    required String? triggerId,
  }) async {
    final trimmedTriggerId = triggerId?.trim();
    if (trimmedTriggerId != null && trimmedTriggerId.isNotEmpty) {
      return _validateExplicitRemoteTrigger(
        actionId: actionId,
        triggerId: trimmedTriggerId,
      );
    }

    final triggersResult = await _repository.listTriggers(
      actionId: actionId,
      isEnabled: true,
      types: const <AgentActionTriggerType>{AgentActionTriggerType.remote},
    );
    if (triggersResult.isError()) {
      return Failure(triggersResult.exceptionOrNull()!);
    }

    final triggers = triggersResult.getOrThrow();
    if (triggers.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote agent action run requires an enabled remote trigger.',
          code: AgentActionFailureCode.remoteTriggerRequired,
          context: {
            'action_id': actionId,
            'reason': AgentActionTriggerConstants.remoteTriggerRequiredReason,
            'user_message':
                'Cadastre e habilite um gatilho remoto para esta acao antes de executar pelo Hub.',
          },
        ),
      );
    }
    if (triggers.length > 1) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Multiple enabled remote triggers found for the action.',
          code: AgentActionFailureCode.remoteTriggerAmbiguous,
          context: {
            'action_id': actionId,
            'trigger_ids': triggers.map((trigger) => trigger.id).toList(growable: false),
            'reason': AgentActionTriggerConstants.remoteTriggerAmbiguousReason,
            'user_message':
                'Esta acao possui mais de um gatilho remoto ativo. Informe trigger_id na chamada do Hub.',
          },
        ),
      );
    }

    return Success(triggers.single.id);
  }

  Future<Result<String>> _validateExplicitRemoteTrigger({
    required String actionId,
    required String triggerId,
  }) async {
    final triggerResult = await _repository.getTrigger(triggerId);
    if (triggerResult.isError()) {
      return Failure(triggerResult.exceptionOrNull()!);
    }

    final trigger = triggerResult.getOrThrow();
    if (trigger.actionId.trim() != actionId) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote trigger does not belong to the requested action.',
          code: AgentActionFailureCode.remoteTriggerInvalid,
          context: {
            'action_id': actionId,
            'trigger_id': trigger.id,
            'trigger_action_id': trigger.actionId,
            'reason': AgentActionTriggerConstants.remoteTriggerActionMismatchReason,
            'user_message': 'O gatilho remoto informado nao pertence a esta acao.',
          },
        ),
      );
    }
    if (trigger.type != AgentActionTriggerType.remote) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Trigger is not a remote logical trigger.',
          code: AgentActionFailureCode.remoteTriggerInvalid,
          context: {
            'action_id': actionId,
            'trigger_id': trigger.id,
            'trigger_type': trigger.type.name,
            'reason': AgentActionTriggerConstants.remoteTriggerTypeMismatchReason,
            'user_message': 'Somente gatilhos do tipo remoto podem ser usados pelo Hub.',
          },
        ),
      );
    }
    if (!trigger.isEnabled) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Remote trigger is disabled.',
          code: AgentActionFailureCode.remoteTriggerInvalid,
          context: {
            'action_id': actionId,
            'trigger_id': trigger.id,
            'reason': AgentActionTriggerConstants.triggerDisabledReason,
            'user_message': 'O gatilho remoto esta desativado.',
          },
        ),
      );
    }

    return Success(trigger.id);
  }
}
