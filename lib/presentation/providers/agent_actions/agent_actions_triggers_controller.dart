import 'dart:collection';

import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/domain/actions/actions.dart';

typedef AgentActionsTriggerStateChanged = void Function();

class AgentActionsTriggersController {
  AgentActionsTriggersController({
    required ListAgentActionTriggers listTriggers,
    required SaveAgentActionTrigger saveTrigger,
    required DeleteAgentActionTrigger deleteTrigger,
    required String Function(Exception failure) messageFor,
    required AgentActionsTriggerStateChanged onStateChanged,
  }) : _listTriggers = listTriggers,
       _saveTrigger = saveTrigger,
       _deleteTrigger = deleteTrigger,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged;

  final ListAgentActionTriggers _listTriggers;
  final SaveAgentActionTrigger _saveTrigger;
  final DeleteAgentActionTrigger _deleteTrigger;
  final String Function(Exception failure) _messageFor;
  final AgentActionsTriggerStateChanged _onStateChanged;

  List<AgentActionTrigger> triggers = <AgentActionTrigger>[];
  bool isLoadingTriggers = false;
  bool isSavingTrigger = false;
  final Set<String> deletingTriggerIds = <String>{};
  String? triggerErrorMessage;

  UnmodifiableListView<AgentActionTrigger>? triggersViewCache;

  UnmodifiableListView<AgentActionTrigger> get triggersView =>
      triggersViewCache ??= UnmodifiableListView<AgentActionTrigger>(triggers);

  void invalidateCaches() {
    triggersViewCache = null;
  }

  bool isDeletingTrigger(String triggerId) => deletingTriggerIds.contains(triggerId);

  void clearTriggerOperationError() {
    if (triggerErrorMessage == null) {
      return;
    }

    triggerErrorMessage = null;
    _onStateChanged();
  }

  Future<bool> saveTrigger({
    required AgentActionTrigger trigger,
    required bool canManageTriggers,
  }) async {
    if (!canManageTriggers || isSavingTrigger) {
      return false;
    }

    isSavingTrigger = true;
    triggerErrorMessage = null;
    _onStateChanged();

    final result = await _saveTrigger(trigger);
    var ok = false;
    result.fold(
      (_) {
        ok = true;
      },
      (Exception failure) {
        triggerErrorMessage = _messageFor(failure);
      },
    );

    isSavingTrigger = false;
    if (!ok) {
      _onStateChanged();
    }

    return ok;
  }

  Future<void> deleteTrigger({
    required String triggerId,
    required bool isFeatureEnabled,
  }) async {
    final trimmedId = triggerId.trim();
    if (!isFeatureEnabled || trimmedId.isEmpty || deletingTriggerIds.contains(trimmedId)) {
      return;
    }

    deletingTriggerIds.add(trimmedId);
    triggerErrorMessage = null;
    _onStateChanged();

    final result = await _deleteTrigger(trimmedId);
    result.fold(
      (_) {},
      (failure) {
        triggerErrorMessage = _messageFor(failure);
      },
    );

    deletingTriggerIds.remove(trimmedId);
  }

  Future<void> syncForSelection({
    required String? actionId,
    required String? selectedActionId,
  }) async {
    if (actionId == null) {
      if (triggers.isNotEmpty || isLoadingTriggers) {
        triggers = <AgentActionTrigger>[];
        isLoadingTriggers = false;
        invalidateCaches();
        _onStateChanged();
      }
      return;
    }

    final expectedActionId = actionId;
    isLoadingTriggers = true;
    _onStateChanged();

    final result = await _listTriggers(actionId: expectedActionId);

    if (selectedActionId != expectedActionId) {
      return;
    }

    if (result.isError()) {
      isLoadingTriggers = false;
      triggerErrorMessage = _messageFor(result.exceptionOrNull()!);
      triggers = <AgentActionTrigger>[];
      invalidateCaches();
      _onStateChanged();
      return;
    }

    final loaded = result.getOrThrow().toList(growable: false);
    loaded.sort((AgentActionTrigger left, AgentActionTrigger right) {
      final leftName = (left.name ?? '').trim();
      final rightName = (right.name ?? '').trim();
      final nameCompare = leftName.toLowerCase().compareTo(rightName.toLowerCase());
      if (nameCompare != 0) {
        return nameCompare;
      }

      return left.id.compareTo(right.id);
    });

    triggers = loaded;
    isLoadingTriggers = false;
    invalidateCaches();
    _onStateChanged();
  }
}
