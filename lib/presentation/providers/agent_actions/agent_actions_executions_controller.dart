import 'dart:collection';

import 'package:plug_agente/application/actions/agent_action_failure_diagnostics.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:result_dart/result_dart.dart';

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
    Future<Result<AgentActionExecution>> Function(String)? cancelIoExecution,
    Future<Result<bool>> Function(String)? ownsIoExecution,
  }) : _listExecutions = listExecutions,
       _runAction = runAction,
       _testDefinition = testDefinition,
       _previewDefinition = previewDefinition,
       _cancelExecution = cancelExecution,
       _cancelIoExecution = cancelIoExecution,
       _ownsIoExecution = ownsIoExecution,
       _messageFor = messageFor,
       _onStateChanged = onStateChanged;

  final ListAgentActionExecutions _listExecutions;
  final RunAgentActionLocally _runAction;
  final TestAgentActionDefinition _testDefinition;
  final PreviewAgentActionDefinition _previewDefinition;
  final CancelAgentActionExecution _cancelExecution;
  final Future<Result<AgentActionExecution>> Function(String)? _cancelIoExecution;
  final Future<Result<bool>> Function(String)? _ownsIoExecution;
  final String Function(Exception failure) _messageFor;
  final AgentActionsExecutionsStateChanged _onStateChanged;

  List<AgentActionExecution> executions = <AgentActionExecution>[];
  bool isRunning = false;
  String? runningManualActionId;
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
            (execution.status == AgentActionExecutionStatus.running &&
                execution.actionType.supportsProcessTermination));
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
    runningManualActionId = definition.id;
    _onStateChanged();

    final result = await _runAction(
      AgentActionExecutionRequest(
        actionId: definition.id,
        source: AgentActionRequestSource.localUi,
        dangerousCommandConfirmed: dangerousCommandConfirmed,
      ),
    );

    isRunning = false;
    runningManualActionId = null;
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

  Future<String?> cancelExecutionById(String executionId) {
    final known = executions.where((execution) => execution.id == executionId).firstOrNull;
    return _cancel(executionId, knownIo: known?.ioStatus != null);
  }

  Future<String?> cancelExecution(AgentActionExecution execution) =>
      _cancel(execution.id, knownIo: execution.ioStatus != null);

  Future<String?> _cancel(String executionId, {required bool knownIo}) async {
    cancellingExecutionIds.add(executionId);
    _onStateChanged();
    try {
      var io = knownIo;
      final ownership = _ownsIoExecution;
      if (!io && ownership != null) io = (await ownership(executionId)).getOrThrow();
      final ioCancel = _cancelIoExecution;
      if (io && ioCancel == null) {
        throw ActionRuntimeFailure.withContext(
          message: 'I/O cancellation is unavailable.',
          code: 'ACTION_IO_CANCEL_UNAVAILABLE',
        );
      }
      final result = io ? await ioCancel!(executionId) : await _cancelExecution(executionId);
      if (result.isError()) return _messageFor(result.exceptionOrNull()!);
      return null;
    } on ActionFailure catch (failure) {
      return _messageFor(failure);
    } on Object catch (error) {
      return _messageFor(
        ActionRuntimeFailure.withContext(
          message: 'Cancellation could not be confirmed.',
          code: 'ACTION_CANCEL_FAILED',
          cause: error,
        ),
      );
    } finally {
      cancellingExecutionIds.remove(executionId);
      _onStateChanged();
    }
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
