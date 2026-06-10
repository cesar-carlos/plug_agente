import 'dart:async';
import 'dart:collection';

import 'package:plug_agente/application/actions/agent_action_remote_audit_support_export.dart';
import 'package:plug_agente/application/use_cases/get_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_recent_agent_action_remote_audit.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/entities/agent_action_remote_audit_record.dart';
import 'package:plug_agente/presentation/providers/agent_action_remote_audit_focus_result.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_definitions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';

typedef AgentActionsRemoteAuditStateChanged = void Function();

class AgentActionsRemoteAuditController {
  AgentActionsRemoteAuditController({
    required ListRecentAgentActionRemoteAudit listRecentRemoteAudit,
    required GetAgentActionExecution getExecution,
    required String Function(Exception failure) messageFor,
    required AgentActionsRemoteAuditStateChanged onStateChanged,
    AgentActionRemoteAuditSupportExport export = const AgentActionRemoteAuditSupportExport(),
  }) : _listRecentRemoteAudit = listRecentRemoteAudit,
       _getExecution = getExecution,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged,
       _export = export;

  final ListRecentAgentActionRemoteAudit _listRecentRemoteAudit;
  final GetAgentActionExecution _getExecution;
  final String Function(Exception failure) _messageFor;
  final AgentActionsRemoteAuditStateChanged _onStateChanged;
  final AgentActionRemoteAuditSupportExport _export;

  List<AgentActionRemoteAuditRecord> entries = <AgentActionRemoteAuditRecord>[];
  String? loadError;
  bool isLoading = false;
  String? auditCorrelationExecutionId;

  UnmodifiableListView<AgentActionRemoteAuditRecord>? entriesViewCache;

  UnmodifiableListView<AgentActionRemoteAuditRecord> get entriesView =>
      entriesViewCache ??= UnmodifiableListView<AgentActionRemoteAuditRecord>(entries);

  void invalidateCaches() {
    entriesViewCache = null;
  }

  void clearCorrelation() {
    auditCorrelationExecutionId = null;
  }

  Future<void> loadDuringBootstrap({required bool remoteAuditEnabled}) async {
    if (remoteAuditEnabled) {
      final auditResult = await _listRecentRemoteAudit();
      auditResult.fold(
        (rows) {
          entries = rows;
          loadError = null;
        },
        (failure) {
          entries = <AgentActionRemoteAuditRecord>[];
          loadError = _messageFor(failure);
        },
      );
    } else {
      entries = <AgentActionRemoteAuditRecord>[];
      loadError = null;
    }
  }

  Future<void> refresh({required bool sectionVisible}) async {
    if (!sectionVisible) {
      return;
    }

    isLoading = true;
    _onStateChanged();

    final auditResult = await _listRecentRemoteAudit();
    auditResult.fold(
      (rows) {
        entries = rows;
        loadError = null;
      },
      (failure) {
        entries = <AgentActionRemoteAuditRecord>[];
        loadError = _messageFor(failure);
      },
    );

    isLoading = false;
    _onStateChanged();
  }

  String buildJsonExport() => _export.buildJson(entries);

  Future<AgentActionRemoteAuditFocusResult> focusExecution({
    required AgentActionRemoteAuditRecord record,
    required bool isFeatureEnabled,
    required AgentActionsDefinitionsController definitionsController,
    required AgentActionsExecutionsController executionsController,
    required AgentActionsHistoryController historyController,
    required DateTime Function() now,
    required Future<void> Function() syncTriggers,
    required Future<void> Function() refreshSecrets,
  }) async {
    if (!isFeatureEnabled) {
      return AgentActionRemoteAuditFocusResult.featureDisabled;
    }

    final actionId = record.actionId?.trim();
    if (actionId == null || actionId.isEmpty) {
      return AgentActionRemoteAuditFocusResult.missingActionId;
    }

    historyController.prepareForRemoteAuditFocus();

    final executionId = record.executionId?.trim();
    final selectionChanged = definitionsController.selectedActionId != actionId;
    definitionsController.selectedActionId = actionId;
    auditCorrelationExecutionId = executionId != null && executionId.isNotEmpty ? executionId : null;

    _onStateChanged();
    unawaited(syncTriggers());
    if (selectionChanged) {
      unawaited(refreshSecrets());
    }

    if (executionId == null || executionId.isEmpty) {
      return AgentActionRemoteAuditFocusResult.succeeded;
    }

    final visible = executionsController
        .filteredSelectedExecutions(
          selectedDefinition: definitionsController.selectedDefinition,
          historyController: historyController,
          now: now,
        )
        .where((AgentActionExecution e) => e.id == executionId)
        .toList(growable: false);
    if (visible.isNotEmpty) {
      if (!_auditRuntimeMatchesExecution(record, visible.single)) {
        auditCorrelationExecutionId = null;
        _onStateChanged();
        return AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch;
      }
      return AgentActionRemoteAuditFocusResult.succeeded;
    }

    final fetched = await _getExecution(executionId, hydrateCapturedOutput: false);
    if (fetched.isError()) {
      auditCorrelationExecutionId = null;
      _onStateChanged();
      return AgentActionRemoteAuditFocusResult.executionNotResolvable;
    }

    final execution = fetched.getOrThrow();
    if (execution.actionId.trim() != actionId) {
      auditCorrelationExecutionId = null;
      _onStateChanged();
      return AgentActionRemoteAuditFocusResult.executionNotResolvable;
    }

    if (!_auditRuntimeMatchesExecution(record, execution)) {
      auditCorrelationExecutionId = null;
      _onStateChanged();
      return AgentActionRemoteAuditFocusResult.runtimeInstanceMismatch;
    }

    _mergeExecutionIntoCache(executionsController, execution);

    final resolvedDefinition = definitionsController.selectedDefinition;
    if (!executionsController
        .filteredSelectedExecutions(
          selectedDefinition: resolvedDefinition,
          historyController: historyController,
          now: now,
        )
        .any((AgentActionExecution e) => e.id == executionId)) {
      auditCorrelationExecutionId = null;
      _onStateChanged();
      return AgentActionRemoteAuditFocusResult.executionNotResolvable;
    }

    return AgentActionRemoteAuditFocusResult.succeeded;
  }

  bool _auditRuntimeMatchesExecution(
    AgentActionRemoteAuditRecord record,
    AgentActionExecution execution,
  ) {
    final auditInstance = record.runtimeInstanceId?.trim();
    if (auditInstance == null || auditInstance.isEmpty) {
      return true;
    }
    final executionInstance = execution.runtimeInstanceId?.trim();
    if (executionInstance == null || executionInstance.isEmpty) {
      return true;
    }
    return auditInstance == executionInstance;
  }

  void _mergeExecutionIntoCache(
    AgentActionsExecutionsController executionsController,
    AgentActionExecution execution,
  ) {
    final merged = <AgentActionExecution>[
      ...executionsController.executions.where((AgentActionExecution e) => e.id != execution.id),
      execution,
    ]..sort((AgentActionExecution a, AgentActionExecution b) => b.requestedAt.compareTo(a.requestedAt));
    executionsController.executions = merged;
    executionsController.invalidateCaches();
    invalidateCaches();
    _onStateChanged();
  }
}
