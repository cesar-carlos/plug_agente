import 'dart:developer' as developer;

import 'package:plug_agente/application/actions/agent_action_trigger_definition_validator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_gate_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentActionTrigger {
  SaveAgentActionTrigger(
    this._repository,
    this._validateTrigger,
    this._featureFlags, {
    AgentActionTriggerScheduler? scheduler,
  }) : _scheduler = scheduler;

  final IAgentActionRepository _repository;
  final ValidateAgentActionTrigger _validateTrigger;
  final FeatureFlags _featureFlags;
  final AgentActionTriggerScheduler? _scheduler;

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
      schedule: validatedTrigger.schedule.copyWith(sourceActionId: validatedTrigger.schedule.sourceActionId?.trim()),
    );

    final definitionResult = await _repository.getDefinition(persistedTrigger.actionId);
    if (definitionResult.isError()) {
      return Failure(definitionResult.exceptionOrNull()!);
    }

    final definition = definitionResult.getOrThrow();
    final compatibility = const AgentActionTriggerDefinitionValidator().validate(persistedTrigger, definition);
    if (compatibility.isError()) return Failure(compatibility.exceptionOrNull()!);
    if (persistedTrigger.isExecutionEventTrigger) {
      final source = persistedTrigger.schedule.sourceActionId!.trim();
      final sourceResult = await _repository.getDefinition(source);
      if (sourceResult.isError()) return Failure(sourceResult.exceptionOrNull()!);
      final triggersResult = await _repository.listTriggers();
      if (triggersResult.isError()) return Failure(triggersResult.exceptionOrNull()!);
      final dependencies = <String, Set<String>>{};
      for (final other in [
        ...triggersResult.getOrThrow().where((item) => item.id != persistedTrigger.id),
        persistedTrigger,
      ]) {
        final dependency = other.schedule.sourceActionId?.trim();
        if (other.isExecutionEventTrigger && dependency != null && dependency.isNotEmpty) {
          dependencies.putIfAbsent(other.actionId, () => <String>{}).add(dependency);
        }
      }
      final pending = <String>[source];
      final visited = <String>{};
      while (pending.isNotEmpty) {
        final action = pending.removeLast();
        if (action == persistedTrigger.actionId) {
          return Failure(
            ActionValidationFailure.withContext(
              message: 'Execution event triggers cannot create dependency cycles.',
              context: const {
                'reason': 'event_trigger_cycle',
                'user_message': 'Este gatilho cria um ciclo entre acoes. Escolha outra origem.',
              },
            ),
          );
        }
        if (visited.add(action)) pending.addAll(dependencies[action] ?? const <String>{});
      }
    }

    final saveResult = await _repository.saveTrigger(persistedTrigger);
    if (saveResult.isError()) {
      return Failure(saveResult.exceptionOrNull()!);
    }

    final savedTrigger = saveResult.getOrThrow();
    await _syncSavedTrigger(savedTrigger);
    return Success(savedTrigger);
  }

  Future<void> _syncSavedTrigger(AgentActionTrigger trigger) async {
    final scheduler = _scheduler;
    if (scheduler == null) {
      return;
    }

    final syncResult = await scheduler.syncTrigger(trigger);
    if (syncResult.isError()) {
      developer.log(
        'Failed to sync saved agent action trigger ${trigger.id} with scheduler',
        name: 'save_agent_action_trigger',
        level: 900,
        error: syncResult.exceptionOrNull(),
      );
    }
  }
}
