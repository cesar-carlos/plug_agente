import '../../helpers/agent_action_use_case_test_support.dart';

void main() {
  late FakeAgentActionRepository repository;

  setUp(() {
    setUpAgentActionUseCaseTests();
    repository = agentActionUseCaseTestRepository;
  });

  group('agent action execution use cases', () {
    test('should save, get and list executions through repository', () async {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
      );

      final saveResult = await SaveAgentActionExecution(repository)(execution);
      final getResult = await GetAgentActionExecution(repository)('execution-1');
      final listResult = await ListAgentActionExecutions(repository)(
        actionId: 'action-1',
        limit: 1,
      );

      expect(saveResult.getOrThrow(), execution);
      expect(getResult.getOrThrow(), execution);
      expect(listResult.getOrThrow(), [execution]);
    });

    test('should reject save execution with blank execution id', () async {
      final execution = AgentActionExecution(
        id: '  ',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
      );

      final result = await SaveAgentActionExecution(repository)(execution);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.executions, isEmpty);
    });

    test('should reject save execution with blank action id', () async {
      final execution = AgentActionExecution(
        id: 'e1',
        actionId: '\t',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
      );

      final result = await SaveAgentActionExecution(repository)(execution);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.executions, isEmpty);
    });

    test('should reject save execution with blank idempotency key when set', () async {
      final execution = AgentActionExecution(
        id: 'e1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: '  ',
      );

      final result = await SaveAgentActionExecution(repository)(execution);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.executions, isEmpty);
    });

    test('should reject get execution with blank id', () async {
      final result = await GetAgentActionExecution(repository)('  ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim id when getting execution', () async {
      final execution = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime(2026),
      );
      repository.executions[execution.id] = execution;

      final result = await GetAgentActionExecution(repository)(' execution-1 ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
    });

    test('should reject list executions with blank action id filter', () async {
      final result = await ListAgentActionExecutions(repository)(actionId: '\t');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should reject list executions with blank idempotency key filter', () async {
      final result = await ListAgentActionExecutions(repository)(idempotencyKey: '  ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim filters when listing executions', () async {
      final execution = AgentActionExecution(
        id: 'e1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'idem-key',
        finishedAt: DateTime(2026),
      );
      repository.executions['e1'] = execution;

      final result = await ListAgentActionExecutions(repository)(
        actionId: '  action-1  ',
        idempotencyKey: ' idem-key ',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), [execution]);
    });

    test('should cleanup executions older than retention window', () async {
      repository.executions['old'] = AgentActionExecution(
        id: 'old',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 10),
      );
      repository.executions['new'] = AgentActionExecution(
        id: 'new',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 14),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 14),
      );

      final result = await CleanupAgentActionExecutions(repository)(
        now: DateTime(2026, 5, 15),
      );

      expect(result.getOrThrow(), 1);
      expect(repository.lastCleanupOlderThan, DateTime(2026, 5, 12));
      expect(repository.executions.keys, ['new']);
    });

    test('should clear captured output older than retention without deleting executions', () async {
      repository.executions['old'] = AgentActionExecution(
        id: 'old',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 10),
        stdoutText: 'stdout blob',
        stderrText: 'stderr blob',
      );
      repository.executions['new'] = AgentActionExecution(
        id: 'new',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 14),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 14),
        stdoutText: 'keep',
      );
      repository.executions['running'] = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 10),
        source: AgentActionRequestSource.scheduler,
        stdoutText: 'still running',
      );

      final result = await CleanupAgentActionCapturedOutput(
        repository,
        retention: const Duration(days: 3),
      )(now: DateTime(2026, 5, 15));

      expect(result.getOrThrow(), 1);
      expect(repository.lastClearCapturedOutputOlderThan, DateTime(2026, 5, 12));
      expect(repository.executions['old']?.stdoutText, isNull);
      expect(repository.executions['old']?.stderrText, isNull);
      expect(repository.executions['new']?.stdoutText, 'keep');
      expect(repository.executions['running']?.stdoutText, 'still running');
    });

    test('should mark queued and running executions as interrupted on bootstrap reconciliation', () async {
      repository.executions['queued'] = AgentActionExecution(
        id: 'queued',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
      );
      repository.executions['running'] = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 1234,
      );
      repository.executions['finished'] = AgentActionExecution(
        id: 'finished',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final useCase = ReconcileAgentActionExecutions(
        repository,
        now: () => DateTime(2026, 5, 15, 10),
      );

      final result = await useCase();
      final secondResult = await useCase();

      expect(result.getOrThrow(), 2);
      expect(secondResult.getOrThrow(), 0);
      expect(repository.executions['queued']?.status, AgentActionExecutionStatus.interrupted);
      expect(repository.executions['running']?.status, AgentActionExecutionStatus.interrupted);
      expect(repository.executions['finished']?.status, AgentActionExecutionStatus.succeeded);
      expect(repository.executions['queued']?.finishedAt, DateTime(2026, 5, 15, 10));
      expect(repository.executions['running']?.failureCode, AgentActionFailureCode.interruptedOnBootstrap);
      expect(repository.executions['running']?.failurePhase, 'bootstrap_reconciliation');
    });

    test('should persist bootstrap reconciliation through SaveAgentActionExecution', () async {
      repository.executions['queued'] = AgentActionExecution(
        id: 'queued',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
      );
      repository.executions['running'] = AgentActionExecution(
        id: 'running',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.scheduler,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 1234,
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final useCase = ReconcileAgentActionExecutions(
        repository,
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 10),
      );

      final result = await useCase();

      expect(result.getOrThrow(), 2);
      expect(countingSave.invocationCount, 2);
    });

    test('should run local action and persist terminal execution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                processExecutable: 'cmd.exe',
                processArgumentCount: 2,
                processCommandPreview: 'cmd.exe /C [REDACTED_COMMAND]',
                stdout: const AgentActionCapturedOutput(
                  text: 'ok',
                  isCaptured: true,
                ),
                stderr: AgentActionCapturedOutput.disabled,
                contextHash: 'sha256:context',
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'key-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(repository.savedExecutions, hasLength(3));
      expect(repository.savedExecutions[0].status, AgentActionExecutionStatus.queued);
      expect(repository.savedExecutions[1].status, AgentActionExecutionStatus.running);
      expect(execution.status, AgentActionExecutionStatus.succeeded);
      expect(execution.pid, 1234);
      expect(execution.processExecutable, 'cmd.exe');
      expect(execution.processArgumentCount, 2);
      expect(execution.processCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
      expect(execution.stdoutText, 'ok');
      expect(execution.contextHash, 'sha256:context');
      expect(execution.idempotencyKey, 'key-1');
    });

    test('should retry local execution when first attempt fails with retriable status', () async {
      repository.definitions['action-retry'] = const AgentActionDefinition(
        id: 'action-retry',
        name: 'Retry command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          retry: AgentActionRetryPolicy(maxAttempts: 2),
        ),
      );
      final runner = RetryThenSucceedAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-retry',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(runner.callCount, 2);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.succeeded);
      expect(result.getOrThrow().exitCode, 0);
    });

    test('should route local run persistence through SaveAgentActionExecution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 9),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'key-1',
        ),
      );

      expect(countingSave.invocationCount, 3);
    });

    test('should persist trimmed idempotency key and optional metadata on local run', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: '  key-1  ',
          requestedBy: '  local-user  ',
          traceId: '  trace-t  ',
          triggerId: '  trig-1  ',
          triggerType: AgentActionTriggerType.manual,
        ),
      );

      final first = repository.savedExecutions.first;
      expect(first.idempotencyKey, 'key-1');
      expect(first.requestedBy, 'local-user');
      expect(first.traceId, 'trace-t');
      expect(first.triggerId, 'trig-1');
    });

    test('should resolve definition when action id has surrounding whitespace', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: '  action-1  ',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().actionId, 'action-1');
    });

    test('should return queued execution immediately when requested', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-key-1',
          returnWhenQueued: true,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final queuedExecution = result.getOrThrow();
      expect(queuedExecution.status, AgentActionExecutionStatus.queued);
      expect(queuedExecution.idempotencyKey, 'remote-key-1');
      await waitForRunnerStarts(runner, 1);
      expect(repository.executions[queuedExecution.id]?.status, AgentActionExecutionStatus.running);

      final repeatedResult = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-key-1',
          returnWhenQueued: true,
        ),
      );

      expect(repeatedResult.isSuccess(), isTrue);
      expect(repeatedResult.getOrThrow().id, queuedExecution.id);
      expect(repeatedResult.getOrThrow().status, AgentActionExecutionStatus.running);
      expect(runner.startedCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.executions[queuedExecution.id]?.status, AgentActionExecutionStatus.succeeded);
    });

    test('should return validateRemoteRun summary without persisting an execution', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-validate-clean',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-validate-key-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final summary = result.getOrThrow();
      expect(summary.actionId, 'action-1');
      expect(summary.actionType, AgentActionType.commandLine);
      expect(summary.definitionSnapshotHash, 'snap-validate-clean');
      expect(summary.wouldReplayExistingExecution, isFalse);
      expect(summary.existingExecutionId, isNull);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should return wouldReplay from persisted idempotency on validateRemoteRun', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-validate-replay',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      repository.executions['exec-prior'] = AgentActionExecution(
        id: 'exec-prior',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 7),
        source: AgentActionRequestSource.remoteHub,
        idempotencyKey: 'idem-replay-1',
        finishedAt: DateTime(2026, 5, 15, 7, 5),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-replay-1',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final summary = result.getOrThrow();
      expect(summary.wouldReplayExistingExecution, isTrue);
      expect(summary.existingExecutionId, 'exec-prior');
      expect(summary.definitionSnapshotHash, 'snap-validate-replay');
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject validateRemoteRun for remote hub without idempotency key', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteIdempotencyRequired);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote run with contextPath on validateRemoteRun', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('validate must not invoke runner')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-1',
          contextPath: r'C:\ctx\input.json',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteContextNotSupported);
      expect(
        failure.context['reason'],
        AgentActionRpcConstants.remoteContextNotSupportedRpcReason,
      );
    });

    test('should reject remote run with runtimeParameters', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-ctx-params',
          runtimeParameters: <String, Object?>{'key': 'value'},
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.code, AgentActionFailureCode.remoteContextNotSupported);
    });

    test('should append remote lifecycle audit rows for remote hub run', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableAgentActionRemoteAudit(true);
      final auditStore = MemoryRemoteAuditStore();
      final lifecycleAudit = AgentActionRemoteLifecycleAuditRecorder(
        featureFlags: flags,
        auditStore: auditStore,
        runtimeIdentity: const AgentRuntimeIdentity(
          runtimeInstanceId: 'inst-test',
          runtimeSessionId: 'sess-test',
        ),
        uuid: const Uuid(),
        now: () => DateTime.utc(2026, 5, 18, 12),
      );
      final runner = FakeAgentActionLocalRunner(
        result: Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        featureFlags: flags,
        remoteLifecycleAudit: lifecycleAudit,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'lifecycle-audit-1',
          traceId: 'trace-lifecycle',
        ),
      );

      expect(result.isSuccess(), isTrue);
      final outcomes = auditStore.rows.map((row) => row.outcome).toList();
      expect(
        outcomes,
        containsAll(<String>[
          AgentActionRemoteAuditConstants.outcomeLifecycleEnqueued,
          AgentActionRemoteAuditConstants.outcomeLifecycleStarted,
          AgentActionRemoteAuditConstants.outcomeLifecycleFinished,
        ]),
      );
      expect(auditStore.rows.first.traceId, 'trace-lifecycle');
    });

    test('should treat validateRemoteRun as would replay when same idempotency run is in flight', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        definitionSnapshotHash: 'snap-in-flight',
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 9),
      );

      await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-in-flight',
          returnWhenQueued: true,
        ),
      );
      await waitForRunnerStarts(runner, 1);

      final validateResult = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-in-flight',
        ),
      );

      expect(validateResult.isSuccess(), isTrue);
      final summary = validateResult.getOrThrow();
      expect(summary.wouldReplayExistingExecution, isTrue);
      expect(summary.existingExecutionId, isNull);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
    });

    test('should persist failed execution when local runner fails', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(
              ActionRuntimeFailure.withContext(
                message: 'Failed to start command line action process.',
                code: AgentActionFailureCode.runtimeError,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.failureCode, AgentActionFailureCode.runtimeError);
      expect(execution.failurePhase, 'process_runtime');
      expect(execution.failureMessage, 'Failed to start command line action process.');
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should persist process metadata from runner failure context', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(
              ActionRuntimeFailure.withContext(
                message: 'Failed to start command line action process.',
                code: AgentActionFailureCode.runtimeError,
                context: const {
                  'executable': 'cmd.exe',
                  'argument_count': 2,
                  'command_preview': 'cmd.exe /C [REDACTED_COMMAND]',
                  'phase': 'start_process',
                },
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.failurePhase, 'start_process');
      expect(execution.processExecutable, 'cmd.exe');
      expect(execution.processArgumentCount, 2);
      expect(execution.processCommandPreview, 'cmd.exe /C [REDACTED_COMMAND]');
    });

    test('should persist rejected exit code as actionable execution failure', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.failed,
                pid: 1234,
                exitCode: 2,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: const AgentActionCapturedOutput(
                  text: 'file not found',
                  isCaptured: true,
                ),
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.failed);
      expect(execution.pid, 1234);
      expect(execution.exitCode, 2);
      expect(execution.failureCode, AgentActionFailureCode.exitCodeRejected);
      expect(execution.failurePhase, 'process_exit');
      expect(execution.failureMessage, 'Command exited with code 2.');
      expect(execution.stderrText, 'file not found');
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should deduplicate local execution by idempotency key', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'same-key',
        ),
      );
      await waitForRunnerStarts(runner, 1);
      final second = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'same-key',
        ),
      );

      expect(runner.startedCount, 1);
      expect(repository.savedExecutions, hasLength(2));
      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      final firstResult = await first;
      final secondResult = await second;

      expect(firstResult.isSuccess(), isTrue);
      expect(secondResult.isSuccess(), isTrue);
      expect(firstResult.getOrThrow().id, secondResult.getOrThrow().id);
      expect(repository.savedExecutions, hasLength(3));
    });

    test('should reuse persisted execution by idempotency key', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'persisted-key',
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: 'persisted-key',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
      expect(runner.startedCount, 0);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reuse persisted execution when idempotency key differs only by whitespace', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        idempotencyKey: 'persisted-key',
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          idempotencyKey: '  persisted-key  ',
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'execution-1');
      expect(runner.startedCount, 0);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should enqueue local execution when concurrency limit is reached', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await waitForRunnerStarts(runner, 1);
      final second = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      await Future<void>.delayed(Duration.zero);
      expect(runner.startedCount, 1);
      expect(repository.savedExecutions.map((execution) => execution.status), [
        AgentActionExecutionStatus.queued,
        AgentActionExecutionStatus.running,
        AgentActionExecutionStatus.queued,
      ]);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
      await waitForRunnerStarts(runner, 2);
      expect(runner.startedCount, 2);
      runner.completions[1].complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 5678,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10, 2),
            finishedAt: DateTime(2026, 5, 15, 10, 3),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      final secondResult = await second;
      expect(secondResult.isSuccess(), isTrue);
      expect(secondResult.getOrThrow().pid, 5678);
    });

    test('should reject local execution when concurrency policy rejects overlap', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            concurrencyBehavior: AgentActionConcurrencyBehavior.reject,
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await waitForRunnerStarts(runner, 1);

      final second = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<ActionQueueFailure>());
      expect(
        (second.exceptionOrNull()! as ActionQueueFailure).code,
        AgentActionFailureCode.queueConcurrencyRejected,
      );
      expect(repository.savedExecutions.last.failureCode, AgentActionFailureCode.queueConcurrencyRejected);
      expect(repository.savedExecutions.last.failurePhase, 'queue');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
    });

    test('should persist ignored overlap as skipped with queueIgnored failure code', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            concurrencyBehavior: AgentActionConcurrencyBehavior.ignore,
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 9),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await waitForRunnerStarts(runner, 1);

      final second = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<ActionQueueFailure>());
      expect(
        (second.exceptionOrNull()! as ActionQueueFailure).code,
        AgentActionFailureCode.queueIgnored,
      );
      expect(repository.savedExecutions.last.status, AgentActionExecutionStatus.skipped);
      expect(repository.savedExecutions.last.failureCode, AgentActionFailureCode.queueIgnored);
      expect(repository.savedExecutions.last.failurePhase, 'queue');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
    });

    test('should reject local execution when action queue is full', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 0,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final runner = ControlledAgentActionLocalRunner();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
      );

      final first = useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await waitForRunnerStarts(runner, 1);

      final second = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(second.isError(), isTrue);
      expect(second.exceptionOrNull(), isA<ActionQueueFailure>());
      expect(
        repository.savedExecutions.last.failureCode,
        AgentActionFailureCode.queueFull,
      );
      expect(repository.savedExecutions.last.failurePhase, 'queue');

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      expect((await first).isSuccess(), isTrue);
    });

    test('should cancel running execution through local runner', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        processStartedAt: DateTime(2026, 5, 15, 9),
        processExecutable: 'cmd.exe',
        pid: 1234,
      );
      final runner = FakeAgentActionLocalRunner(
        result: Failure(ActionRuntimeFailure('Should not run')),
        cancelResult: const Success(
          AgentActionCancellationResult(
            executionId: 'execution-1',
            status: AgentActionExecutionStatus.killed,
            killed: true,
            pid: 1234,
            message: 'Processo principal finalizado.',
          ),
        ),
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([
          runner,
        ]),
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final result = await useCase('execution-1');

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.killed);
      expect(execution.finishedAt, DateTime(2026, 5, 15, 9, 1));
      expect(execution.failureCode, AgentActionFailureCode.executionKilled);
      expect(execution.failurePhase, 'cancel');
      expect(runner.lastExpectedPid, 1234);
      expect(runner.lastExpectedProcessExecutable, 'cmd.exe');
      expect(runner.lastExpectedProcessStartedAt, DateTime(2026, 5, 15, 9));
      expect(repository.savedExecutions.last.status, AgentActionExecutionStatus.killed);
    });

    test('should cancel running elevated execution through elevated canceller', () async {
      repository.definitions['action-elevated'] = const AgentActionDefinition(
        id: 'action-elevated',
        name: 'Elevated command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'whoami'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      repository.executions['execution-elevated'] = AgentActionExecution(
        id: 'execution-elevated',
        actionId: 'action-elevated',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 0,
      );
      final elevatedCanceller = FakeElevatedActionExecutionCanceller(
        cancelResult: const Success(
          AgentActionCancellationResult(
            executionId: 'execution-elevated',
            status: AgentActionExecutionStatus.killed,
            killed: true,
            pid: 0,
            message: 'Elevated process cancelled.',
          ),
        ),
      );
      final runner = FakeAgentActionLocalRunner(
        result: Failure(ActionRuntimeFailure('Should not run')),
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        elevatedCanceller: elevatedCanceller,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final result = await useCase('execution-elevated');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().status, AgentActionExecutionStatus.killed);
      expect(result.getOrThrow().failureCode, AgentActionFailureCode.executionKilled);
      expect(elevatedCanceller.lastExecutionId, 'execution-elevated');
      expect(runner.cancelInvocationCount, 0);
    });

    test('should persist running cancel through SaveAgentActionExecution', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.running,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        processStartedAt: DateTime(2026, 5, 15, 9),
        pid: 1234,
      );
      final runner = FakeAgentActionLocalRunner(
        result: Failure(ActionRuntimeFailure('Should not run')),
        cancelResult: const Success(
          AgentActionCancellationResult(
            executionId: 'execution-1',
            status: AgentActionExecutionStatus.killed,
            killed: true,
            pid: 1234,
            message: 'Processo principal finalizado.',
          ),
        ),
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final result = await useCase('execution-1');

      expect(result.isSuccess(), isTrue);
      expect(countingSave.invocationCount, 1);
    });

    test('should reject cancel when execution already finished', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.succeeded,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
        finishedAt: DateTime(2026, 5, 15, 9, 1),
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
      );

      final result = await useCase('execution-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionRuntimeFailure>());
      expect(
        (result.exceptionOrNull()! as ActionRuntimeFailure).context,
        containsPair('reason', AgentActionRpcConstants.agentActionCancelAlreadyFinishedErrorReason),
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should cancel queued execution before runner starts', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final queue = ActionExecutionQueue();
      final runner = ControlledAgentActionLocalRunner();
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        executionQueue: queue,
      );
      final cancelUseCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        executionQueue: queue,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final first = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await waitForRunnerStarts(runner, 1);
      final second = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final queuedExecution = repository.savedExecutions.last;

      final cancelResult = await cancelUseCase(queuedExecution.id);

      expect(cancelResult.isSuccess(), isTrue);
      expect(cancelResult.getOrThrow().status, AgentActionExecutionStatus.cancelled);
      expect(cancelResult.getOrThrow().failureCode, AgentActionFailureCode.queueCancelled);
      expect(cancelResult.getOrThrow().failurePhase, 'queue');
      expect(runner.startedCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      expect((await first).isSuccess(), isTrue);
      final secondResult = await second;
      expect(secondResult.isError(), isTrue);
      expect(repository.executions[queuedExecution.id]?.status, AgentActionExecutionStatus.cancelled);
    });

    test('should persist queued cancel through SaveAgentActionExecution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          queue: AgentActionQueuePolicy(
            maxQueued: 1,
            queueTimeout: Duration(seconds: 5),
          ),
        ),
      );
      final queue = ActionExecutionQueue();
      final runner = ControlledAgentActionLocalRunner();
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        executionQueue: queue,
      );
      final countingSave = CountingSaveAgentActionExecution(repository);
      final cancelUseCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        executionQueue: queue,
        saveExecution: countingSave,
        now: () => DateTime(2026, 5, 15, 9, 1),
      );

      final first = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await waitForRunnerStarts(runner, 1);
      final second = runUseCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final queuedExecution = repository.savedExecutions.last;

      final cancelResult = await cancelUseCase(queuedExecution.id);

      expect(cancelResult.isSuccess(), isTrue);
      expect(countingSave.invocationCount, 1);

      runner.completions.first.complete(
        Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );

      expect((await first).isSuccess(), isTrue);
      await second;
    });

    test('should reject cancel when queued execution is not in memory queue', () async {
      repository.executions['execution-1'] = AgentActionExecution(
        id: 'execution-1',
        actionId: 'action-1',
        actionType: AgentActionType.commandLine,
        status: AgentActionExecutionStatus.queued,
        requestedAt: DateTime(2026, 5, 15, 9),
        source: AgentActionRequestSource.localUi,
      );
      final useCase = CancelAgentActionExecution(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
      );

      final result = await useCase('execution-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
      expect(
        (result.exceptionOrNull()! as ActionNotFoundFailure).context,
        containsPair('reason', AgentActionQueueConstants.queuedExecutionNotFoundReason),
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject local execution when action is not active', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.paused,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject execution when agent actions feature flag is disabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActions(false);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.featureDisabled);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote ad-hoc execution when remote ad-hoc feature flag is disabled', () async {
      repository.definitions['action-adhoc'] = AgentActionDefinition(
        id: 'action-adhoc',
        name: 'Remote ad-hoc',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            allowAdHoc: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-adhoc',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-adhoc-1',
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.remoteAdHocDisabled,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution when remote feature flag is disabled', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.remoteFeatureDisabled,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution when secret rotation invalidates risk fingerprint', () async {
      final secretStore = InMemoryAgentActionSecretStoreForRunTests();
      await secretStore.saveSecret('api', 'version-one');
      const snapshotter = AgentActionDefinitionSnapshotter();
      final fingerprinter = AgentActionSecretReferenceFingerprinter(secretStore);
      const baseDefinition = AgentActionDefinition(
        id: 'action-1',
        name: 'Secret action',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: r'echo ${secret:api}'),
      );
      final approvedFingerprints = await fingerprinter.fingerprintsFor(baseDefinition);
      final approvedDefinition = baseDefinition.copyWith(
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026, 5, 15),
            approvedBy: 'local-admin',
            riskFingerprint: snapshotter.riskFingerprint(
              baseDefinition,
              secretReferenceFingerprints: approvedFingerprints,
            ),
          ),
        ),
      );
      repository.definitions['action-1'] = approvedDefinition;

      await secretStore.saveSecret('api', 'version-two');

      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        definitionSnapshotter: snapshotter,
        secretReferenceFingerprinter: fingerprinter,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'idem-1',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.remoteNotApproved);
      expect(
        failure.context['reason'],
        AgentActionGateConstants.remoteRiskFingerprintStaleReason,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution when action is not approved for remote use', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.remoteNotApproved);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution without idempotency key', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.remoteIdempotencyRequired,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject execution request with invalid runtime parameters before queueing', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
          runtimeParameters: {
            'invalid': Duration(seconds: 1),
          },
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).context,
        containsPair('reason', AgentActionValidationConstants.invalidRuntimeParametersReason),
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution when runner is not configured', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService();
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.elevatedNotConfigured,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution when runner is degraded', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService()..markDegraded(reason: 'test');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.elevatedRunnerDegraded,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution for unsupported action type', () async {
      final tempDir = await Directory.systemTemp.createTemp('elevated_type_gate_');
      addTearDown(() => tempDir.delete(recursive: true));
      final storage = GlobalStorageContext(appDirectoryPath: tempDir.path);
      final marker = File(AgentActionElevatedConstants.readyMarkerPath(tempDir.path));
      await marker.parent.create(recursive: true);
      await marker.writeAsString('ok');

      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Send mail',
        state: AgentActionState.active,
        config: EmailActionConfig(
          smtpProfileId: 'smtp-1',
          from: 'agent@example.com',
          to: ['ops@example.com'],
          subjectTemplate: 'subject',
          bodyTemplate: 'body',
        ),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(true);
      final readiness = ElevatedActionRunnerReadinessService()..refresh(storage);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        elevatedRunnerReadiness: readiness,
        elevatedExecutionService: ElevatedAgentActionExecutionService(
          bridge: NoOpElevatedBridge(),
          statusFileSyncer: ElevatedActionStatusFileSyncer(storageContext: storage),
          readiness: readiness,
        ),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(
        (result.exceptionOrNull()! as ActionValidationFailure).code,
        AgentActionFailureCode.unsupportedForElevatedRunner,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject elevated execution when elevated feature flag is disabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableElevatedAgentActions(false);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.elevatedDisabled);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject scheduled execution when maintenance mode is enabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.scheduler,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.maintenanceMode);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should allow local execution when maintenance mode is enabled without strict mode', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final runtimeStateGuard = AgentActionRuntimeStateGuard(flags)..markMaintenance(reason: 'operator');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 10),
                finishedAt: DateTime(2026, 5, 15, 10, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        runtimeStateGuard: runtimeStateGuard,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isSuccess(), isTrue);
      expect(repository.savedExecutions, isNotEmpty);
    });

    test('should reject local execution when maintenance strict mode is enabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      await flags.setEnableAgentActionsMaintenanceStrictMode(true);
      final runtimeStateGuard = AgentActionRuntimeStateGuard(flags)..markMaintenance(reason: 'operator');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        runtimeStateGuard: runtimeStateGuard,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect((result.exceptionOrNull()! as ActionAuthorizationFailure).code, AgentActionFailureCode.maintenanceMode);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should reject remote execution while subsystem is draining', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runtimeStateGuard = AgentActionRuntimeStateGuard()..markDraining(reason: 'shutdown');
      final useCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
        runtimeStateGuard: runtimeStateGuard,
        featureFlags: flags,
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-1',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-key-1',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.subsystemDraining);
      expect(failure.context['reason'], AgentActionRuntimeStateConstants.agentActionsDrainingReason);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should block dangerous remote hub runs even when warn mode is enabled', () async {
      repository.definitions['action-dangerous'] = AgentActionDefinition(
        id: 'action-dangerous',
        name: 'Dangerous',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'format C: /Y'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableAgentActionDangerousCommandWarnMode(true);
      final useCase = runUseCaseWithDangerousCommandPolicy(
        repository: repository,
        featureFlags: flags,
        runnerResult: Failure(ActionRuntimeFailure('Should not run')),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-dangerous',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-dangerous-1',
        ),
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(
        failure.context['reason'],
        AgentActionCommandSafetyConstants.dangerousCommandPatternReason,
      );
      expect(repository.savedExecutions, isEmpty);
    });

    test('should block dangerous scheduler runs even when warn mode is enabled', () async {
      repository.definitions['action-dangerous'] = const AgentActionDefinition(
        id: 'action-dangerous',
        name: 'Dangerous',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'format C: /Y'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionDangerousCommandWarnMode(true);
      final useCase = runUseCaseWithDangerousCommandPolicy(
        repository: repository,
        featureFlags: flags,
        runnerResult: Failure(ActionRuntimeFailure('Should not run')),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-dangerous',
          source: AgentActionRequestSource.scheduler,
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });

    test('should require dangerous command confirmation for local UI warn mode', () async {
      repository.definitions['action-dangerous'] = const AgentActionDefinition(
        id: 'action-dangerous',
        name: 'Dangerous',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'format C: /Y'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionDangerousCommandWarnMode(true);
      final useCase = runUseCaseWithDangerousCommandPolicy(
        repository: repository,
        featureFlags: flags,
        runnerResult: Failure(ActionRuntimeFailure('Should not run')),
      );

      final blocked = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-dangerous',
          source: AgentActionRequestSource.localUi,
        ),
      );

      expect(blocked.isError(), isTrue);
      final failure = blocked.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['confirmation_required'], isTrue);
      expect(repository.savedExecutions, isEmpty);
    });

    test('should allow local UI warn mode when dangerous command is confirmed', () async {
      repository.definitions['action-dangerous'] = const AgentActionDefinition(
        id: 'action-dangerous',
        name: 'Dangerous',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'format C: /Y'),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionDangerousCommandWarnMode(true);
      final runner = FakeAgentActionLocalRunner(
        result: Success(
          AgentActionProcessResult(
            status: AgentActionExecutionStatus.succeeded,
            pid: 1234,
            exitCode: 0,
            processStartedAt: DateTime(2026, 5, 15, 10),
            finishedAt: DateTime(2026, 5, 15, 10, 1),
            stdout: AgentActionCapturedOutput.disabled,
            stderr: AgentActionCapturedOutput.disabled,
            redactionApplied: true,
          ),
        ),
      );
      final useCase = runUseCaseWithDangerousCommandPolicy(
        repository: repository,
        featureFlags: flags,
        runnerResult: runner.result,
        runners: <AgentActionLocalRunner>[runner],
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await useCase(
        const AgentActionExecutionRequest(
          actionId: 'action-dangerous',
          source: AgentActionRequestSource.localUi,
          dangerousCommandConfirmed: true,
        ),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.status, AgentActionExecutionStatus.succeeded);
    });

    test('should reject dangerous commands on validateRemoteRun', () async {
      repository.definitions['action-dangerous'] = AgentActionDefinition(
        id: 'action-dangerous',
        name: 'Dangerous',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'format C: /Y'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime(2026, 5, 15, 8),
            approvedBy: 'local-admin',
          ),
        ),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      await flags.setEnableAgentActionDangerousCommandWarnMode(true);
      final useCase = runUseCaseWithDangerousCommandPolicy(
        repository: repository,
        featureFlags: flags,
        runnerResult: Failure(ActionRuntimeFailure('validate must not invoke runner')),
      );

      final result = await useCase.validateRemoteRun(
        const AgentActionExecutionRequest(
          actionId: 'action-dangerous',
          source: AgentActionRequestSource.remoteHub,
          idempotencyKey: 'remote-validate-dangerous',
        ),
      );

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });

    test('validation and authorization action failures are not recoverable', () {
      expect(
        ActionValidationFailure.withContext(message: 'invalid').isRecoverable,
        isFalse,
      );
      expect(
        ActionAuthorizationFailure.withContext(message: 'denied').isRecoverable,
        isFalse,
      );
      expect(ActionRuntimeFailure('runtime').isRecoverable, isTrue);
    });
  });
}
