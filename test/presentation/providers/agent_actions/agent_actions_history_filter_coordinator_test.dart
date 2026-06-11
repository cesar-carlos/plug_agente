import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_filter_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';

class _MockListExecutions extends Mock implements ListAgentActionExecutions {}

class _MockRunAction extends Mock implements RunAgentActionLocally {}

class _MockTestDefinition extends Mock implements TestAgentActionDefinition {}

class _MockPreviewDefinition extends Mock implements PreviewAgentActionDefinition {}

class _MockCancelExecution extends Mock implements CancelAgentActionExecution {}

class _MockListRemoteAudit extends Mock implements ListRecentAgentActionRemoteAudit {}

class _MockGetExecution extends Mock implements GetAgentActionExecution {}

void main() {
  test('setHistoryStatusFilter notifies and clears audit correlation', () {
    var notifyCount = 0;
    final history = AgentActionsHistoryController();
    final executions = AgentActionsExecutionsController(
      listExecutions: _MockListExecutions(),
      runAction: _MockRunAction(),
      testDefinition: _MockTestDefinition(),
      previewDefinition: _MockPreviewDefinition(),
      cancelExecution: _MockCancelExecution(),
      messageFor: (_) => 'err',
      onStateChanged: () {},
    );
    final remoteAudit = AgentActionsRemoteAuditController(
      listRecentRemoteAudit: _MockListRemoteAudit(),
      getExecution: _MockGetExecution(),
      messageFor: (_) => 'err',
      onStateChanged: () {},
    );
    remoteAudit.auditCorrelationExecutionId = 'exec-1';

    final coordinator = AgentActionsHistoryFilterCoordinator(
      historyController: history,
      executionsController: executions,
      remoteAuditController: remoteAudit,
      onFiltersChanged: () => notifyCount++,
      reloadExecutionsForPeriod: () async {},
    );

    coordinator.setStatusFilter(AgentActionExecutionStatus.failed);

    expect(history.statusFilter, AgentActionExecutionStatus.failed);
    expect(remoteAudit.auditCorrelationExecutionId, isNull);
    expect(notifyCount, 1);
  });
}
