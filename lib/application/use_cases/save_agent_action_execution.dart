import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentActionExecution {
  const SaveAgentActionExecution(
    IAgentActionRepository repository, {
    Future<void> Function(AgentActionExecution)? onTerminalExecution,
  }) : _repository = repository,
       _onTerminalExecution = onTerminalExecution;

  final IAgentActionRepository _repository;
  final Future<void> Function(AgentActionExecution)? _onTerminalExecution;

  Future<Result<AgentActionExecution>> call(
    AgentActionExecution execution,
  ) async {
    if (execution.id.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Execution id is required to save an action execution.',
          context: const {
            'field': 'id',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Informe o identificador da execucao antes de salvar.',
          },
        ),
      );
    }

    if (execution.actionId.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action id is required to save an action execution.',
          context: const {
            'field': 'actionId',
            'reason': AgentActionValidationConstants.fieldRequiredReason,
            'user_message': 'Provide the action linked to this execution before saving.',
          },
        ),
      );
    }

    final idempotencyKey = execution.idempotencyKey;
    if (idempotencyKey != null && idempotencyKey.trim().isEmpty) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Idempotency key cannot be blank when set on an action execution.',
          context: const {
            'field': 'idempotencyKey',
            'reason': AgentActionValidationConstants.blankValueReason,
            'user_message': 'Remova a chave de idempotencia ou informe um valor valido.',
          },
        ),
      );
    }

    final listener = _onTerminalExecution;
    var shouldNotify = false;
    if (listener != null && execution.isTerminal) {
      final previous = await _repository.getExecution(execution.id, hydrateCapturedOutput: false);
      if (previous.isError() && previous.exceptionOrNull() is! ActionNotFoundFailure) {
        return Failure(previous.exceptionOrNull()!);
      }
      shouldNotify = previous.isSuccess() && !previous.getOrThrow().isTerminal;
    }
    final result = await _repository.saveExecution(execution);
    if (result.isSuccess() && shouldNotify && listener != null) {
      unawaited(_notifyTerminal(listener, result.getOrThrow()));
    }
    return result;
  }

  Future<void> _notifyTerminal(
    Future<void> Function(AgentActionExecution) listener,
    AgentActionExecution execution,
  ) async {
    try {
      await listener(execution);
    } on Object catch (error, stackTrace) {
      developer.log(
        'Failed to dispatch action completion event',
        name: 'save_agent_action_execution',
        level: 900,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
