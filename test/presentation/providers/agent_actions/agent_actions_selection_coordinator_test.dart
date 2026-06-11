import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/ports/i_agent_actions_bundle_file_gateway.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/delete_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/export_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/import_agent_actions_bundle.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/list_developer_data7_connections.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_bundle_transfer_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_selection_coordinator.dart';
import 'package:uuid/uuid.dart';

class _MockSaveDefinition extends Mock implements SaveAgentActionDefinition {}

class _MockDeleteDefinition extends Mock implements DeleteAgentActionDefinition {}

class _MockListDeveloperConnections extends Mock implements ListDeveloperData7Connections {}

class _MockListExecutions extends Mock implements ListAgentActionExecutions {}

class _MockRunAction extends Mock implements RunAgentActionLocally {}

class _MockTestDefinition extends Mock implements TestAgentActionDefinition {}

class _MockPreviewDefinition extends Mock implements PreviewAgentActionDefinition {}

class _MockCancelExecution extends Mock implements CancelAgentActionExecution {}

class _MockListRemoteAudit extends Mock implements ListRecentAgentActionRemoteAudit {}

class _MockGetExecution extends Mock implements GetAgentActionExecution {}

class _MockExportBundle extends Mock implements ExportAgentActionsBundle {}

class _MockImportBundle extends Mock implements ImportAgentActionsBundle {}

class _MockBundleFileGateway extends Mock implements IAgentActionsBundleFileGateway {}

AgentActionsSelectionCoordinator _coordinator({
  required AgentActionsDefinitionsController definitions,
  required AgentActionsExecutionsController executions,
  required AgentActionsRemoteAuditController remoteAudit,
  required AgentActionsBundleTransferController bundleTransfer,
  void Function()? onNotify,
  AgentActionDefinition? Function()? selectedDefinition,
  bool Function()? canDeleteSelected,
  bool Function()? canRunSelected,
  bool Function()? canTestSelected,
  bool Function(AgentActionExecution)? canCancelExecution,
  bool Function()? canTransferBundle,
  Future<void> Function()? reload,
  Future<void> Function()? syncTriggers,
  Future<void> Function()? refreshSecrets,
}) {
  return AgentActionsSelectionCoordinator(
    definitionsController: definitions,
    executionsController: executions,
    remoteAuditController: remoteAudit,
    bundleTransferController: bundleTransfer,
    notifyStateChanged: onNotify ?? () {},
    setErrorMessage: (_) {},
    reload: reload ?? () async {},
    syncTriggersForSelection: syncTriggers ?? () async {},
    refreshSelectedSecretReport: refreshSecrets ?? () async {},
    selectedDefinition: selectedDefinition ?? () => null,
    canDeleteSelected: canDeleteSelected ?? () => false,
    canRunSelected: canRunSelected ?? () => false,
    canTestSelected: canTestSelected ?? () => false,
    canCancelExecution: canCancelExecution ?? (_) => false,
    canTransferBundle: canTransferBundle ?? () => false,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AgentActionDefinition(
        id: 'fallback',
        name: 'Fallback',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      ),
    );
  });

  group('AgentActionsSelectionCoordinator', () {
    test('selectAction clears audit correlation and notifies', () async {
      var notifyCount = 0;
      var syncedTriggers = false;
      var refreshedSecrets = false;

      final definitions = AgentActionsDefinitionsController(
        saveDefinition: _MockSaveDefinition(),
        deleteDefinition: _MockDeleteDefinition(),
        listDeveloperData7Connections: _MockListDeveloperConnections(),
        uuid: const Uuid(),
        messageFor: (_) => 'err',
        onStateChanged: () {},
      );
      definitions.definitions = [
        const AgentActionDefinition(
          id: 'action-1',
          name: 'One',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
        ),
        const AgentActionDefinition(
          id: 'action-2',
          name: 'Two',
          state: AgentActionState.active,
          config: CommandLineActionConfig(command: 'dir'),
        ),
      ];
      definitions.selectedActionId = 'action-1';

      final executions = AgentActionsExecutionsController(
        listExecutions: _MockListExecutions(),
        runAction: _MockRunAction(),
        testDefinition: _MockTestDefinition(),
        previewDefinition: _MockPreviewDefinition(),
        cancelExecution: _MockCancelExecution(),
        messageFor: (_) => 'err',
        onStateChanged: () {},
      );
      executions.lastTestedActionId = 'action-1';

      final remoteAudit = AgentActionsRemoteAuditController(
        listRecentRemoteAudit: _MockListRemoteAudit(),
        getExecution: _MockGetExecution(),
        messageFor: (_) => 'err',
        onStateChanged: () {},
      );
      remoteAudit.auditCorrelationExecutionId = 'exec-1';

      final coordinator = _coordinator(
        definitions: definitions,
        executions: executions,
        remoteAudit: remoteAudit,
        bundleTransfer: AgentActionsBundleTransferController(
          exportBundle: _MockExportBundle(),
          importBundle: _MockImportBundle(),
          bundleFileGateway: _MockBundleFileGateway(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        onNotify: () => notifyCount++,
        syncTriggers: () async => syncedTriggers = true,
        refreshSecrets: () async => refreshedSecrets = true,
      );

      coordinator.selectAction('action-2');

      expect(definitions.selectedActionId, 'action-2');
      expect(remoteAudit.auditCorrelationExecutionId, isNull);
      expect(executions.lastTestedActionId, isNull);
      expect(notifyCount, 1);
      await pumpEventQueue();
      expect(syncedTriggers, isTrue);
      expect(refreshedSecrets, isTrue);
    });

    test('selectAction is no-op when action id unchanged', () {
      var notifyCount = 0;
      final definitions = AgentActionsDefinitionsController(
        saveDefinition: _MockSaveDefinition(),
        deleteDefinition: _MockDeleteDefinition(),
        listDeveloperData7Connections: _MockListDeveloperConnections(),
        uuid: const Uuid(),
        messageFor: (_) => 'err',
        onStateChanged: () {},
      );
      definitions.selectedActionId = 'action-1';

      final coordinator = _coordinator(
        definitions: definitions,
        executions: AgentActionsExecutionsController(
          listExecutions: _MockListExecutions(),
          runAction: _MockRunAction(),
          testDefinition: _MockTestDefinition(),
          previewDefinition: _MockPreviewDefinition(),
          cancelExecution: _MockCancelExecution(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        remoteAudit: AgentActionsRemoteAuditController(
          listRecentRemoteAudit: _MockListRemoteAudit(),
          getExecution: _MockGetExecution(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        bundleTransfer: AgentActionsBundleTransferController(
          exportBundle: _MockExportBundle(),
          importBundle: _MockImportBundle(),
          bundleFileGateway: _MockBundleFileGateway(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        onNotify: () => notifyCount++,
      );

      coordinator.selectAction('action-1');

      expect(notifyCount, 0);
    });

    test('exportBundleToFile returns false when transfer not allowed', () async {
      final coordinator = _coordinator(
        definitions: AgentActionsDefinitionsController(
          saveDefinition: _MockSaveDefinition(),
          deleteDefinition: _MockDeleteDefinition(),
          listDeveloperData7Connections: _MockListDeveloperConnections(),
          uuid: const Uuid(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        executions: AgentActionsExecutionsController(
          listExecutions: _MockListExecutions(),
          runAction: _MockRunAction(),
          testDefinition: _MockTestDefinition(),
          previewDefinition: _MockPreviewDefinition(),
          cancelExecution: _MockCancelExecution(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        remoteAudit: AgentActionsRemoteAuditController(
          listRecentRemoteAudit: _MockListRemoteAudit(),
          getExecution: _MockGetExecution(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        bundleTransfer: AgentActionsBundleTransferController(
          exportBundle: _MockExportBundle(),
          importBundle: _MockImportBundle(),
          bundleFileGateway: _MockBundleFileGateway(),
          messageFor: (_) => 'err',
          onStateChanged: () {},
        ),
        canTransferBundle: () => false,
      );

      final succeeded = await coordinator.exportBundleToFile(
        'bundle.json',
        l10n: lookupAppLocalizations(const Locale('en')),
      );

      expect(succeeded, isFalse);
    });
  });
}
