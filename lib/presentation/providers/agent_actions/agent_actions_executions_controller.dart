import 'dart:collection';

import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';

typedef AgentActionsExecutionsStateChanged = void Function();

class AgentActionsExecutionsController {
  AgentActionsExecutionsController({
    required ListAgentActionExecutions listExecutions,
    required RunAgentActionLocally runAction,
    required TestAgentActionDefinition testDefinition,
    required PreviewAgentActionDefinition previewDefinition,
    required CancelAgentActionExecution cancelExecution,
    required String Function(Exception failure) messageFor,
    required AgentActionsExecutionsStateChanged onStateChanged,
  }) : _listExecutions = listExecutions,
       _runAction = runAction,
       _testDefinition = testDefinition,
       _previewDefinition = previewDefinition,
       _cancelExecution = cancelExecution,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged;

  final ListAgentActionExecutions _listExecutions;
  final RunAgentActionLocally _runAction;
  final TestAgentActionDefinition _testDefinition;
  final PreviewAgentActionDefinition _previewDefinition;
  final CancelAgentActionExecution _cancelExecution;
  final String Function(Exception failure) _messageFor;
  final AgentActionsExecutionsStateChanged _onStateChanged;

  List<AgentActionExecution> executions = <AgentActionExecution>[];
  bool isRunning = false;
  bool isTesting = false;
  final Set<String> cancellingExecutionIds = <String>{};
  String? lastTestedActionId;
  bool? lastTestCanRun;
  String? lastTestCommandPreview;
  String? lastTestPreviewErrorMessage;
  Map<String, Object?> lastTestDiagnostics = const <String, Object?>{};

  UnmodifiableListView<AgentActionExecution>? executionsViewCache;
  List<AgentActionExecution>? filteredSelectedExecutionsCache;

  UnmodifiableListView<AgentActionExecution> get executionsView =>
      executionsViewCache ??= UnmodifiableListView<AgentActionExecution>(executions);

  void invalidateCaches() {
    executionsViewCache = null;
    filteredSelectedExecutionsCache = null;
  }

  void clearLastTestPreviewState() {
    lastTestCommandPreview = null;
    lastTestPreviewErrorMessage = null;
    lastTestDiagnostics = const <String, Object?>{};
  }

  void clearTestStateForSelectionChange() {
    lastTestedActionId = null;
    lastTestCanRun = null;
    clearLastTestPreviewState();
  }

  bool hasCancellationInProgress(String executionId) => cancellingExecutionIds.contains(executionId);

  bool canCancelExecution({
    required AgentActionExecution execution,
    required bool isFeatureEnabled,
  }) {
    return isFeatureEnabled &&
        !execution.isTerminal &&
        !hasCancellationInProgress(execution.id) &&
        (execution.status == AgentActionExecutionStatus.queued ||
            execution.status == AgentActionExecutionStatus.running);
  }

  int get queuedCount => executions.where((execution) => execution.status == AgentActionExecutionStatus.queued).length;

  int get runningCount =>
      executions.where((execution) => execution.status == AgentActionExecutionStatus.running).length;

  int get failedCount => executions.where((execution) => execution.status == AgentActionExecutionStatus.failed).length;

  bool hasActiveExecutionForDefinition(String definitionId) {
    return executions.any(
      (execution) => execution.actionId == definitionId && !execution.isTerminal,
    );
  }

  List<AgentActionExecution> filteredSelectedExecutions({
    required AgentActionDefinition? selectedDefinition,
    required AgentActionsHistoryController historyController,
    required DateTime Function() now,
  }) {
    final cached = filteredSelectedExecutionsCache;
    if (cached != null) {
      return cached;
    }

    final selected = selectedDefinition;
    if (selected == null) {
      return const <AgentActionExecution>[];
    }

    final filtered = executions
        .where(
          (execution) => historyController.matchesExecution(
            execution: execution,
            selectedActionId: selected.id,
            now: now,
          ),
        )
        .toList(growable: false);

    filtered.sort((left, right) => right.requestedAt.compareTo(left.requestedAt));
    return filteredSelectedExecutionsCache = List<AgentActionExecution>.unmodifiable(filtered);
  }

  Future<String?> reloadForPeriod({
    required AgentActionsHistoryController historyController,
    required DateTime Function() now,
    required bool isLoading,
    required int Function() nextPeriodReloadGeneration,
    required bool Function(int generation) isPeriodReloadCurrent,
  }) async {
    if (isLoading) {
      return null;
    }

    final generation = nextPeriodReloadGeneration();
    final result = await _listExecutions(
      requestedAfter: historyController.periodStart(now),
      limit: historyController.executionFetchLimit(),
    );

    if (!isPeriodReloadCurrent(generation) || isLoading) {
      return null;
    }

    return result.fold(
      (loadedExecutions) {
        executions = loadedExecutions;
        invalidateCaches();
        _onStateChanged();
        return null;
      },
      _messageFor,
    );
  }

  Future<String?> runAction({
    required AgentActionDefinition definition,
    required bool dangerousCommandConfirmed,
  }) async {
    isRunning = true;
    _onStateChanged();

    final result = await _runAction(
      AgentActionExecutionRequest(
        actionId: definition.id,
        source: AgentActionRequestSource.localUi,
        dangerousCommandConfirmed: dangerousCommandConfirmed,
      ),
    );

    isRunning = false;
    if (result.isError()) {
      final message = _messageFor(result.exceptionOrNull()!);
      _onStateChanged();
      return message;
    }

    return null;
  }

  Future<({String? errorMessage, bool preflightRecorded})> testAction({
    required AgentActionDefinition definition,
    required Future<void> Function(AgentActionDefinition definition) onPreflightSuccess,
    required void Function(String definitionId) onPreflightFailure,
  }) async {
    isTesting = true;
    lastTestedActionId = null;
    lastTestCanRun = null;
    clearLastTestPreviewState();
    _onStateChanged();

    final result = await _testDefinition(definition.id);
    if (result.isError()) {
      final failure = result.exceptionOrNull()!;
      lastTestedActionId = definition.id;
      lastTestCanRun = false;
      onPreflightFailure(definition.id);
      final errorMessage = _messageFor(failure);
      _applyTestFailurePreview(failure);
      isTesting = false;
      _onStateChanged();
      return (errorMessage: errorMessage, preflightRecorded: false);
    }

    final preflight = result.getOrThrow();
    lastTestedActionId = definition.id;
    lastTestCanRun = preflight.canRun;
    lastTestDiagnostics = preflight.redactedDiagnostics;

    await onPreflightSuccess(definition);

    final previewResult = await _previewDefinition(definition.id);
    previewResult.fold(
      (preview) {
        lastTestCommandPreview = preview.redactedCommandPreview;
        lastTestDiagnostics = <String, Object?>{
          ...lastTestDiagnostics,
          ...preview.redactedDiagnostics,
        };
        lastTestPreviewErrorMessage = null;
      },
      (failure) {
        lastTestCommandPreview = null;
        lastTestPreviewErrorMessage = _messageFor(failure);
      },
    );

    isTesting = false;
    _onStateChanged();
    return (errorMessage: null, preflightRecorded: true);
  }

  Future<String?> cancelExecution(AgentActionExecution execution) async {
    cancellingExecutionIds.add(execution.id);
    _onStateChanged();

    final result = await _cancelExecution(execution.id);

    cancellingExecutionIds.remove(execution.id);
    if (result.isError()) {
      final message = _messageFor(result.exceptionOrNull()!);
      _onStateChanged();
      return message;
    }

    return null;
  }

  void _applyTestFailurePreview(Exception failure) {
    lastTestCommandPreview = null;
    lastTestPreviewErrorMessage = _messageFor(failure);
    if (failure is ActionFailure) {
      lastTestDiagnostics = const AgentActionFailureDiagnosticsResolver().redactedDiagnosticsForTestPreview(failure);
    } else {
      lastTestDiagnostics = const <String, Object?>{};
    }
  }
}
