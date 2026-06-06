import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';

void main() {
  group('AgentActionsHistoryController', () {
    test('applyRestored reports period changes without mutating when unchanged', () {
      final controller = AgentActionsHistoryController();
      final result = controller.applyRestored(
        historyStatus: null,
        historySource: null,
        historyPeriod: AgentActionHistoryPeriod.last3Days,
        historyFailurePhase: null,
        historySearch: '',
      );

      expect(result.didChange, isFalse);
      expect(result.periodChanged, isFalse);
    });

    test('matchesExecution respects period and status filters', () {
      final controller = AgentActionsHistoryController()
        ..statusFilter = AgentActionExecutionStatus.failed
        ..periodFilter = AgentActionHistoryPeriod.last24Hours;

      final now = DateTime(2026, 6, 6, 12);
      final execution = AgentActionExecution(
        id: 'exec-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.failed,
        source: AgentActionRequestSource.localUi,
        requestedAt: now.subtract(const Duration(hours: 2)),
      );

      expect(
        controller.matchesExecution(
          execution: execution,
          selectedActionId: 'action-1',
          now: () => now,
        ),
        isTrue,
      );

      controller.statusFilter = AgentActionExecutionStatus.succeeded;
      expect(
        controller.matchesExecution(
          execution: execution,
          selectedActionId: 'action-1',
          now: () => now,
        ),
        isFalse,
      );
    });

    test('clearFilters resets to defaults', () {
      final controller = AgentActionsHistoryController()
        ..statusFilter = AgentActionExecutionStatus.failed
        ..periodFilter = AgentActionHistoryPeriod.all
        ..searchQuery = 'needle';

      controller.clearFilters();

      expect(controller.hasFilters, isFalse);
      expect(controller.periodFilter, AgentActionHistoryPeriod.last3Days);
      expect(controller.searchQuery, isEmpty);
    });
  });
}
