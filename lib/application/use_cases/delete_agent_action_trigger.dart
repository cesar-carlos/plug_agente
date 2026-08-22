import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class DeleteAgentActionTrigger {
  const DeleteAgentActionTrigger(
    this._repository, {
    AgentActionTriggerScheduler? scheduler,
  }) : _scheduler = scheduler;

  final IAgentActionRepository _repository;
  final AgentActionTriggerScheduler? _scheduler;

  Future<Result<void>> call(String id) async {
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger id is required for delete.',
          context: const {
            'field': 'id',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o identificador do gatilho antes de excluir.',
          },
        ),
      );
    }

    final deleteResult = await _repository.deleteTrigger(trimmed);
    if (deleteResult.isSuccess()) {
      _scheduler?.unscheduleTrigger(trimmed);
    }
    return deleteResult;
  }
}
