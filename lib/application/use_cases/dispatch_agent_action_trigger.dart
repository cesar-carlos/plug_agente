import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class DispatchAgentActionTrigger {
  DispatchAgentActionTrigger(
    this._repository,
    this._runAction, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final IAgentActionRepository _repository;
  final RunAgentActionLocally _runAction;
  final DateTime Function() _now;

  Future<Result<AgentActionExecution>> call({
    required String triggerId,
    DateTime? scheduledAt,
    String? idempotencyKey,
    String? requestedBy,
    String? traceId,
  }) async {
    final trimmedTriggerId = triggerId.trim();
    if (trimmedTriggerId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger id is required to dispatch a trigger.',
          context: const {
            'field': 'triggerId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o gatilho que sera disparado.',
          },
        ),
      );
    }

    final triggerResult = await _repository.getTrigger(trimmedTriggerId);
    if (triggerResult.isError()) {
      return Failure(triggerResult.exceptionOrNull()!);
    }

    final trigger = triggerResult.getOrThrow();
    final actionId = trigger.actionId.trim();
    if (actionId.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger references a blank action id.',
          code: AgentActionFailureCode.triggerActionIdBlank,
          context: {
            'trigger_id': trigger.id,
            'reason': AgentActionTriggerConstants.blankActionIdReason,
            'user_message': 'O gatilho referencia uma acao invalida. Corrija o cadastro do gatilho.',
          },
        ),
      );
    }

    if (!trigger.isEnabled) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger is disabled and cannot be dispatched.',
          context: {
            'trigger_id': trigger.id,
            'action_id': actionId,
            'reason': AgentActionTriggerConstants.triggerDisabledReason,
            'user_message': 'O gatilho esta desativado e nao pode executar a acao.',
          },
        ),
      );
    }

    return _runAction(
      AgentActionExecutionRequest(
        actionId: actionId,
        source: _sourceFor(trigger.type),
        idempotencyKey: _idempotencyKeyFor(
          trigger: trigger,
          scheduledAt: scheduledAt,
          idempotencyKey: idempotencyKey,
        ),
        requestedBy: requestedBy?.trim(),
        traceId: traceId?.trim(),
        triggerId: trigger.id,
        triggerType: trigger.type,
        scheduledAt: scheduledAt,
        triggeredAt: _now(),
      ),
    );
  }

  AgentActionRequestSource _sourceFor(AgentActionTriggerType type) {
    return switch (type) {
      AgentActionTriggerType.manual => AgentActionRequestSource.localUi,
      AgentActionTriggerType.remote => AgentActionRequestSource.remoteHub,
      AgentActionTriggerType.appStart || AgentActionTriggerType.appClose => AgentActionRequestSource.appLifecycle,
      AgentActionTriggerType.once ||
      AgentActionTriggerType.interval ||
      AgentActionTriggerType.daily ||
      AgentActionTriggerType.weekly ||
      AgentActionTriggerType.monthly => AgentActionRequestSource.scheduler,
    };
  }

  String? _idempotencyKeyFor({
    required AgentActionTrigger trigger,
    required DateTime? scheduledAt,
    required String? idempotencyKey,
  }) {
    final trimmedIdempotencyKey = idempotencyKey?.trim();
    if (trimmedIdempotencyKey != null && trimmedIdempotencyKey.isNotEmpty) {
      return trimmedIdempotencyKey;
    }

    if (scheduledAt == null) {
      return null;
    }

    return 'trigger:${trigger.id}:${scheduledAt.toUtc().toIso8601String()}';
  }
}
