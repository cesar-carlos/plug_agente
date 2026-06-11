import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_remote_audit_controller.dart';

/// Remote audit refresh, export, and execution-focus flows for agent actions UI.
final class AgentActionsRemoteAuditCoordinator {
  AgentActionsRemoteAuditCoordinator({
    required AgentActionsRemoteAuditController remoteAuditController,
    required AgentActionsDefinitionsController definitionsController,
    required AgentActionsExecutionsController executionsController,
    required AgentActionsHistoryController historyController,
    required bool Function() isFeatureEnabled,
    required bool Function() isRemoteAuditSectionVisible,
    required DateTime Function() now,
    required Future<void> Function() syncTriggers,
    required Future<void> Function() refreshSecrets,
  }) : _remoteAuditController = remoteAuditController,
       _definitionsController = definitionsController,
       _executionsController = executionsController,
       _historyController = historyController,
       _isFeatureEnabled = isFeatureEnabled,
       _isRemoteAuditSectionVisible = isRemoteAuditSectionVisible,
       _now = now,
       _syncTriggers = syncTriggers,
       _refreshSecrets = refreshSecrets;

  final AgentActionsRemoteAuditController _remoteAuditController;
  final AgentActionsDefinitionsController _definitionsController;
  final AgentActionsExecutionsController _executionsController;
  final AgentActionsHistoryController _historyController;
  final bool Function() _isFeatureEnabled;
  final bool Function() _isRemoteAuditSectionVisible;
  final DateTime Function() _now;
  final Future<void> Function() _syncTriggers;
  final Future<void> Function() _refreshSecrets;

  Future<void> refresh() => _remoteAuditController.refresh(sectionVisible: _isRemoteAuditSectionVisible());

  String buildJsonExport() => _remoteAuditController.buildJsonExport();

  Future<AgentActionRemoteAuditFocusResult> focusExecutionFromRemoteAudit(
    AgentActionRemoteAuditRecord record,
  ) => _remoteAuditController.focusExecution(
    record: record,
    isFeatureEnabled: _isFeatureEnabled(),
    definitionsController: _definitionsController,
    executionsController: _executionsController,
    historyController: _historyController,
    now: _now,
    syncTriggers: _syncTriggers,
    refreshSecrets: _refreshSecrets,
  );
}
