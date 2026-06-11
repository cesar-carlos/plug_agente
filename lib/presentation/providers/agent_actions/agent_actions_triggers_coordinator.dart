import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_triggers_controller.dart';

/// Trigger save/delete and selection sync for agent actions UI.
final class AgentActionsTriggersCoordinator {
  AgentActionsTriggersCoordinator({
    required AgentActionsTriggersController triggersController,
    required AgentActionsDefinitionsController definitionsController,
    required bool Function() canManageTriggers,
    required bool Function() isFeatureEnabled,
    required String? Function() selectedActionId,
  }) : _triggersController = triggersController,
       _definitionsController = definitionsController,
       _canManageTriggers = canManageTriggers,
       _isFeatureEnabled = isFeatureEnabled,
       _selectedActionId = selectedActionId;

  final AgentActionsTriggersController _triggersController;
  final AgentActionsDefinitionsController _definitionsController;
  final bool Function() _canManageTriggers;
  final bool Function() _isFeatureEnabled;
  final String? Function() _selectedActionId;

  bool isDeletingTrigger(String triggerId) => _triggersController.isDeletingTrigger(triggerId);

  void clearTriggerOperationError() => _triggersController.clearTriggerOperationError();

  Future<void> refreshTriggersForSelection() => _syncTriggersForSelection();

  Future<bool> saveTrigger(AgentActionTrigger trigger) async {
    final ok = await _triggersController.saveTrigger(
      trigger: trigger,
      canManageTriggers: _canManageTriggers(),
    );
    if (ok) {
      await _syncTriggersForSelection();
    }
    return ok;
  }

  Future<void> deleteTrigger(String triggerId) async {
    await _triggersController.deleteTrigger(
      triggerId: triggerId,
      isFeatureEnabled: _isFeatureEnabled(),
    );
    await _syncTriggersForSelection();
  }

  Future<void> _syncTriggersForSelection() => _triggersController.syncForSelection(
    actionId: _selectedActionId(),
    selectedActionId: _definitionsController.selectedActionId,
  );
}
