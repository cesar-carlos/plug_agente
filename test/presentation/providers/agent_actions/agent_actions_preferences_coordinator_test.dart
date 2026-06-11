import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_preferences_coordinator.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';
import 'package:uuid/uuid.dart';

class _MockListExecutions extends Mock implements ListAgentActionExecutions {}

class _MockRunAction extends Mock implements RunAgentActionLocally {}

class _MockTestDefinition extends Mock implements TestAgentActionDefinition {}

class _MockPreviewDefinition extends Mock implements PreviewAgentActionDefinition {}

class _MockCancelExecution extends Mock implements CancelAgentActionExecution {}

class _MockListRemoteAudit extends Mock implements ListRecentAgentActionRemoteAudit {}

class _MockGetExecution extends Mock implements GetAgentActionExecution {}

class _MockSaveDefinition extends Mock implements SaveAgentActionDefinition {}

class _MockDeleteDefinition extends Mock implements DeleteAgentActionDefinition {}

class _MockListDeveloperConnections extends Mock implements ListDeveloperData7Connections {}

class _MockUuid extends Mock implements Uuid {}

void main() {
  late AgentActionsDefinitionsController definitions;
  late AgentActionsExecutionsController executions;
  late AgentActionsRemoteAuditController remoteAudit;

  setUp(() {
    definitions = AgentActionsDefinitionsController(
      saveDefinition: _MockSaveDefinition(),
      deleteDefinition: _MockDeleteDefinition(),
      listDeveloperData7Connections: _MockListDeveloperConnections(),
      uuid: _MockUuid(),
      messageFor: (_) => 'err',
      onStateChanged: () {},
    );
    executions = AgentActionsExecutionsController(
      listExecutions: _MockListExecutions(),
      runAction: _MockRunAction(),
      testDefinition: _MockTestDefinition(),
      previewDefinition: _MockPreviewDefinition(),
      cancelExecution: _MockCancelExecution(),
      messageFor: (_) => 'err',
      onStateChanged: () {},
    );
    remoteAudit = AgentActionsRemoteAuditController(
      listRecentRemoteAudit: _MockListRemoteAudit(),
      getExecution: _MockGetExecution(),
      messageFor: (_) => 'err',
      onStateChanged: () {},
    );
  });

  test('applyRestoredPreferences notifies and clears audit correlation when filters change', () {
    var notifyCount = 0;
    final history = AgentActionsHistoryController();
    remoteAudit.auditCorrelationExecutionId = 'exec-1';

    final coordinator = AgentActionsPreferencesCoordinator(
      historyController: history,
      definitionsController: definitions,
      executionsController: executions,
      remoteAuditController: remoteAudit,
      onPreferencesChanged: () => notifyCount++,
      reloadExecutionsForPeriod: () async {},
    );

    coordinator.applyRestoredPreferences(
      definitionType: AgentActionType.commandLine,
      definitionState: null,
      definitionSearch: '',
      historyStatus: null,
      historySource: null,
      historyPeriod: AgentActionHistoryPeriod.last3Days,
      historyFailurePhase: null,
      historySearch: '',
    );

    expect(definitions.definitionTypeFilter, AgentActionType.commandLine);
    expect(remoteAudit.auditCorrelationExecutionId, isNull);
    expect(notifyCount, 1);
  });

  test('applyRestoredPreferences is no-op when restored values match current state', () {
    var notifyCount = 0;
    final history = AgentActionsHistoryController();

    final coordinator = AgentActionsPreferencesCoordinator(
      historyController: history,
      definitionsController: definitions,
      executionsController: executions,
      remoteAuditController: remoteAudit,
      onPreferencesChanged: () => notifyCount++,
      reloadExecutionsForPeriod: () async {},
    );

    coordinator.applyRestoredPreferences(
      definitionType: null,
      definitionState: null,
      definitionSearch: '',
      historyStatus: null,
      historySource: null,
      historyPeriod: AgentActionHistoryPeriod.last3Days,
      historyFailurePhase: null,
      historySearch: '',
    );

    expect(notifyCount, 0);
  });
}
