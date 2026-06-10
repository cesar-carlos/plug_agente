import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_triggers.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_triggers_controller.dart';
import 'package:result_dart/result_dart.dart';

class _MockListTriggers extends Mock implements ListAgentActionTriggers {}

class _MockSaveTrigger extends Mock implements SaveAgentActionTrigger {}

class _MockDeleteTrigger extends Mock implements DeleteAgentActionTrigger {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AgentActionTrigger(
        id: 'fallback',
        actionId: 'action-1',
        type: AgentActionTriggerType.manual,
      ),
    );
  });

  late _MockListTriggers listTriggers;
  late _MockSaveTrigger saveTrigger;
  late _MockDeleteTrigger deleteTrigger;
  late int stateChangeCount;
  late AgentActionsTriggersController controller;

  AgentActionsTriggersController buildController() {
    return AgentActionsTriggersController(
      listTriggers: listTriggers,
      saveTrigger: saveTrigger,
      deleteTrigger: deleteTrigger,
      messageFor: (failure) => failure.toString(),
      onStateChanged: () => stateChangeCount++,
    );
  }

  setUp(() {
    listTriggers = _MockListTriggers();
    saveTrigger = _MockSaveTrigger();
    deleteTrigger = _MockDeleteTrigger();
    stateChangeCount = 0;
    controller = buildController();
  });

  group('AgentActionsTriggersController syncForSelection', () {
    test('clears triggers when action id is null', () async {
      controller
        ..triggers = const [
          AgentActionTrigger(
            id: 'trig-1',
            actionId: 'action-1',
            type: AgentActionTriggerType.manual,
          ),
        ]
        ..isLoadingTriggers = true;
      stateChangeCount = 0;

      await controller.syncForSelection(actionId: null, selectedActionId: null);

      expect(controller.triggers, isEmpty);
      expect(controller.isLoadingTriggers, isFalse);
      expect(stateChangeCount, 1);
      verifyNever(() => listTriggers(actionId: any(named: 'actionId')));
    });

    test('loads and sorts triggers for selected action', () async {
      when(() => listTriggers(actionId: 'action-1')).thenAnswer(
        (_) async => const Success([
          AgentActionTrigger(
            id: 'trig-z',
            actionId: 'action-1',
            type: AgentActionTriggerType.daily,
            name: 'Zulu',
          ),
          AgentActionTrigger(
            id: 'trig-a',
            actionId: 'action-1',
            type: AgentActionTriggerType.manual,
            name: 'Alpha',
          ),
        ]),
      );

      await controller.syncForSelection(
        actionId: 'action-1',
        selectedActionId: 'action-1',
      );

      expect(controller.isLoadingTriggers, isFalse);
      expect(controller.triggerErrorMessage, isNull);
      expect(controller.triggers.map((trigger) => trigger.id), ['trig-a', 'trig-z']);
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('surfaces list failure in triggerErrorMessage', () async {
      final failure = ActionValidationFailure('Cannot list triggers.');
      when(() => listTriggers(actionId: 'action-1')).thenAnswer((_) async => Failure(failure));

      await controller.syncForSelection(
        actionId: 'action-1',
        selectedActionId: 'action-1',
      );

      expect(controller.triggers, isEmpty);
      expect(controller.triggerErrorMessage, failure.toString());
    });

    test('ignores stale response when selection changed during load', () async {
      when(() => listTriggers(actionId: 'action-1')).thenAnswer(
        (_) async => const Success([
          AgentActionTrigger(
            id: 'trig-1',
            actionId: 'action-1',
            type: AgentActionTriggerType.manual,
          ),
        ]),
      );

      await controller.syncForSelection(
        actionId: 'action-1',
        selectedActionId: 'action-2',
      );

      expect(controller.triggers, isEmpty);
      expect(controller.isLoadingTriggers, isTrue);
    });
  });

  group('AgentActionsTriggersController mutations', () {
    const trigger = AgentActionTrigger(
      id: 'trig-1',
      actionId: 'action-1',
      type: AgentActionTriggerType.manual,
    );

    test('saveTrigger returns true on success', () async {
      when(() => saveTrigger(trigger)).thenAnswer((_) async => const Success(trigger));

      final ok = await controller.saveTrigger(
        trigger: trigger,
        canManageTriggers: true,
      );

      expect(ok, isTrue);
      expect(controller.triggerErrorMessage, isNull);
      expect(controller.isSavingTrigger, isFalse);
    });

    test('saveTrigger surfaces validation failure', () async {
      final failure = ActionValidationFailure('Trigger schedule is invalid.');
      when(() => saveTrigger(trigger)).thenAnswer((_) async => Failure(failure));

      final ok = await controller.saveTrigger(
        trigger: trigger,
        canManageTriggers: true,
      );

      expect(ok, isFalse);
      expect(controller.triggerErrorMessage, failure.toString());
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('saveTrigger returns false when management is disabled', () async {
      final ok = await controller.saveTrigger(
        trigger: trigger,
        canManageTriggers: false,
      );

      expect(ok, isFalse);
      verifyNever(() => saveTrigger(any()));
    });

    test('deleteTrigger tracks deleting ids and surfaces failure', () async {
      final failure = ActionNotFoundFailure('Trigger was not found.');
      when(() => deleteTrigger('trig-1')).thenAnswer((_) async => Failure(failure));

      await controller.deleteTrigger(
        triggerId: 'trig-1',
        isFeatureEnabled: true,
      );

      expect(controller.isDeletingTrigger('trig-1'), isFalse);
      expect(controller.triggerErrorMessage, failure.toString());
    });

    test('clearTriggerOperationError notifies listeners', () {
      controller.triggerErrorMessage = 'Something failed';
      stateChangeCount = 0;

      controller.clearTriggerOperationError();

      expect(controller.triggerErrorMessage, isNull);
      expect(stateChangeCount, 1);
    });
  });
}
