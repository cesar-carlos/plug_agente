import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/cancel_agent_action_execution.dart';
import 'package:plug_agente/application/use_cases/list_agent_action_executions.dart';
import 'package:plug_agente/application/use_cases/preview_agent_action_definition.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/test_agent_action_definition.dart';
import 'package:plug_agente/domain/actions/action_io_execution_status.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_executions_controller.dart';
import 'package:plug_agente/presentation/providers/agent_actions/agent_actions_history_controller.dart';
import 'package:result_dart/result_dart.dart';

class _MockListExecutions extends Mock implements ListAgentActionExecutions {}

class _MockRunAction extends Mock implements RunAgentActionLocally {}

class _MockTestDefinition extends Mock implements TestAgentActionDefinition {}

class _MockPreviewDefinition extends Mock implements PreviewAgentActionDefinition {}

class _MockCancelExecution extends Mock implements CancelAgentActionExecution {}

class _FakeExecutionRequest extends Fake implements AgentActionExecutionRequest {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const AgentActionExecutionRequest(
        actionId: 'action-1',
        source: AgentActionRequestSource.localUi,
      ),
    );
    registerFallbackValue(_FakeExecutionRequest());
  });

  final now = DateTime(2026, 6, 6, 12);

  late _MockListExecutions listExecutions;
  late _MockRunAction runAction;
  late _MockTestDefinition testDefinition;
  late _MockPreviewDefinition previewDefinition;
  late _MockCancelExecution cancelExecution;
  late int stateChangeCount;
  late AgentActionsExecutionsController controller;
  late AgentActionsHistoryController historyController;

  AgentActionsExecutionsController buildController({
    Future<Result<AgentActionExecution>> Function(String)? cancelIo,
    Future<Result<bool>> Function(String)? ownsIo,
  }) {
    return AgentActionsExecutionsController(
      listExecutions: listExecutions,
      runAction: runAction,
      testDefinition: testDefinition,
      previewDefinition: previewDefinition,
      cancelExecution: cancelExecution,
      cancelIoExecution: cancelIo,
      ownsIoExecution: ownsIo,
      messageFor: (failure) => failure.toString(),
      onStateChanged: () => stateChangeCount++,
    );
  }

  setUp(() {
    listExecutions = _MockListExecutions();
    runAction = _MockRunAction();
    testDefinition = _MockTestDefinition();
    previewDefinition = _MockPreviewDefinition();
    cancelExecution = _MockCancelExecution();
    stateChangeCount = 0;
    controller = buildController();
    historyController = AgentActionsHistoryController();
  });

  test('routes faithful cancellation locally and never falls back when unavailable', () async {
    final execution = AgentActionExecution(
      id: 'io',
      actionId: 'a',
      actionType: AgentActionType.executable,
      status: AgentActionExecutionStatus.running,
      requestedAt: now,
      source: AgentActionRequestSource.remoteHub,
      ioStatus: const ActionIoExecutionStatus(
        processState: 'running',
        stdinState: 'open',
        captureState: 'capturing',
        outputExpired: false,
      ),
    );
    var ioCalls = 0;
    controller = buildController(
      cancelIo: (id) async {
        expect(id, 'io');
        ioCalls++;
        return Success(execution);
      },
    );
    controller.executions = [execution];
    expect(await controller.cancelExecution(execution), isNull);
    expect(await controller.cancelExecutionById('io'), isNull);
    expect(ioCalls, 2);
    verifyZeroInteractions(cancelExecution);
    controller = buildController();
    expect(await controller.cancelExecution(execution), contains('ACTION_IO_CANCEL_UNAVAILABLE'));
    verifyZeroInteractions(cancelExecution);
  });

  test('unloaded I/O IDs use journal ownership and storage failure never falls back', () async {
    var calls = 0;
    final stopped = AgentActionExecution(
      id: 'unloaded',
      actionId: 'a',
      actionType: AgentActionType.executable,
      status: AgentActionExecutionStatus.cancelled,
      requestedAt: now,
      source: AgentActionRequestSource.remoteHub,
    );
    controller = buildController(
      ownsIo: (_) async => const Success(true),
      cancelIo: (_) async {
        calls++;
        return Success(stopped);
      },
    );
    expect(await controller.cancelExecutionById('unloaded'), isNull);
    expect(calls, 1);
    verifyZeroInteractions(cancelExecution);
    controller = buildController(
      ownsIo: (_) async => Failure(
        ActionRuntimeFailure.withContext(message: 'Storage unavailable.', code: 'ACTION_IO_STORAGE_UNAVAILABLE'),
      ),
    );
    expect(await controller.cancelExecutionById('unloaded'), contains('ACTION_IO_STORAGE_UNAVAILABLE'));
    expect(controller.cancellingExecutionIds, isEmpty);
    verifyZeroInteractions(cancelExecution);
  });

  test('running email and COM cannot be cancelled, but their queued executions can', () {
    for (final type in [AgentActionType.email, AgentActionType.comObject]) {
      final execution = AgentActionExecution(
        id: 'execution',
        actionId: 'a',
        actionType: type,
        status: AgentActionExecutionStatus.running,
        requestedAt: now,
        source: AgentActionRequestSource.localUi,
      );
      expect(controller.canCancelExecution(execution: execution, isFeatureEnabled: true), isFalse);
      expect(
        controller.canCancelExecution(
          execution: execution.copyWith(status: AgentActionExecutionStatus.queued),
          isFeatureEnabled: true,
        ),
        isTrue,
      );
    }
  });

  group('AgentActionsExecutionsController status helpers', () {
    setUp(() {
      controller.executions = [
        AgentActionExecution(
          id: 'queued',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.queued,
          requestedAt: now,
          source: AgentActionRequestSource.localUi,
        ),
        AgentActionExecution(
          id: 'running',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.running,
          requestedAt: now,
          source: AgentActionRequestSource.localUi,
        ),
        AgentActionExecution(
          id: 'failed',
          actionId: 'action-2',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.failed,
          requestedAt: now,
          source: AgentActionRequestSource.scheduler,
        ),
      ];
    });

    test('counts queued, running and failed executions', () {
      expect(controller.queuedCount, 1);
      expect(controller.runningCount, 1);
      expect(controller.failedCount, 1);
    });

    test('detects active execution for definition', () {
      expect(controller.hasActiveExecutionForDefinition('action-1'), isTrue);
      expect(controller.hasActiveExecutionForDefinition('action-2'), isFalse);
    });

    test('canCancelExecution respects terminal state and in-flight cancellation', () {
      final running = controller.executions[1];
      expect(
        controller.canCancelExecution(execution: running, isFeatureEnabled: true),
        isTrue,
      );

      controller.cancellingExecutionIds.add(running.id);
      expect(
        controller.canCancelExecution(execution: running, isFeatureEnabled: true),
        isFalse,
      );
    });
  });

  group('AgentActionsExecutionsController filteredSelectedExecutions', () {
    const selectedDefinition = AgentActionDefinition(
      id: 'action-1',
      name: 'Run',
      config: CommandLineActionConfig(command: 'dir'),
    );

    setUp(() {
      controller.executions = [
        AgentActionExecution(
          id: 'recent-failed',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.failed,
          requestedAt: now.subtract(const Duration(hours: 2)),
          source: AgentActionRequestSource.scheduler,
        ),
        AgentActionExecution(
          id: 'recent-success',
          actionId: 'action-1',
          actionType: AgentActionType.commandLine,
          status: AgentActionExecutionStatus.succeeded,
          requestedAt: now.subtract(const Duration(hours: 1)),
          source: AgentActionRequestSource.localUi,
        ),
      ];
      historyController
        ..statusFilter = AgentActionExecutionStatus.failed
        ..sourceFilter = AgentActionRequestSource.scheduler
        ..periodFilter = AgentActionHistoryPeriod.last24Hours;
    });

    test('filters and sorts selected action history', () {
      final filtered = controller.filteredSelectedExecutions(
        selectedDefinition: selectedDefinition,
        historyController: historyController,
        now: () => now,
      );

      expect(filtered.map((execution) => execution.id), ['recent-failed']);
    });

    test('returns empty list when no definition is selected', () {
      expect(
        controller.filteredSelectedExecutions(
          selectedDefinition: null,
          historyController: historyController,
          now: () => now,
        ),
        isEmpty,
      );
    });
  });

  group('AgentActionsExecutionsController operations', () {
    const definition = AgentActionDefinition(
      id: 'action-1',
      name: 'Run',
      config: CommandLineActionConfig(command: 'dir'),
    );

    test('runAction toggles isRunning and returns error message on failure', () async {
      final failure = ActionValidationFailure('Run blocked.');
      when(() => runAction(any())).thenAnswer((_) async => Failure(failure));

      final pending = controller.runAction(
        definition: definition,
        dangerousCommandConfirmed: false,
      );
      expect(controller.isRunning, isTrue);

      final message = await pending;

      expect(message, failure.toString());
      expect(controller.isRunning, isFalse);
      expect(stateChangeCount, greaterThanOrEqualTo(2));
    });

    test('testAction records preview on success', () async {
      when(() => testDefinition('action-1')).thenAnswer(
        (_) async => const Success(
          AgentActionPreflight(
            actionType: AgentActionType.commandLine,
            canRun: true,
          ),
        ),
      );
      when(() => previewDefinition('action-1')).thenAnswer(
        (_) async => const Success(
          AgentActionPreparedExecution(
            actionType: AgentActionType.commandLine,
            redactedCommandPreview: 'cmd.exe /C ***',
          ),
        ),
      );

      final result = await controller.testAction(
        definition: definition,
        onPreflightSuccess: (_) async {},
        onPreflightFailure: (_) {},
      );

      expect(result.errorMessage, isNull);
      expect(result.preflightRecorded, isTrue);
      expect(controller.lastTestedActionId, 'action-1');
      expect(controller.lastTestCanRun, isTrue);
      expect(controller.lastTestCommandPreview, 'cmd.exe /C ***');
      expect(controller.isTesting, isFalse);
    });

    test('testAction surfaces failure preview state', () async {
      final failure = ActionValidationFailure('Preflight failed.');
      when(() => testDefinition('action-1')).thenAnswer((_) async => Failure(failure));

      var preflightFailureCalled = false;
      final result = await controller.testAction(
        definition: definition,
        onPreflightSuccess: (_) async {},
        onPreflightFailure: (_) => preflightFailureCalled = true,
      );

      expect(result.errorMessage, failure.toString());
      expect(result.preflightRecorded, isFalse);
      expect(preflightFailureCalled, isTrue);
      expect(controller.lastTestCanRun, isFalse);
      expect(controller.lastTestPreviewErrorMessage, failure.toString());
    });

    test('clearTestStateForSelectionChange resets preview fields', () {
      controller
        ..lastTestedActionId = 'action-1'
        ..lastTestCanRun = true
        ..lastTestCommandPreview = 'preview'
        ..lastTestPreviewErrorMessage = 'error';

      controller.clearTestStateForSelectionChange();

      expect(controller.lastTestedActionId, isNull);
      expect(controller.lastTestCanRun, isNull);
      expect(controller.lastTestCommandPreview, isNull);
      expect(controller.lastTestPreviewErrorMessage, isNull);
    });

    test('cancelExecution tracks cancelling ids and returns error message', () async {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: now,
        source: AgentActionRequestSource.localUi,
      );
      final failure = ActionRuntimeFailure('Cancel failed.');
      when(() => cancelExecution('execution-1')).thenAnswer((_) async => Failure(failure));

      final pending = controller.cancelExecution(execution);
      expect(controller.hasCancellationInProgress('execution-1'), isTrue);

      final message = await pending;

      expect(message, failure.toString());
      expect(controller.hasCancellationInProgress('execution-1'), isFalse);
    });
  });
}
