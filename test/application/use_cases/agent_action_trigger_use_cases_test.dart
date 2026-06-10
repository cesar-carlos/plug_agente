import '../../helpers/agent_action_use_case_test_support.dart';

void main() {
  late FakeAgentActionRepository repository;
  late FeatureFlags featureFlags;

  setUp(() {
    setUpAgentActionUseCaseTests();
    repository = agentActionUseCaseTestRepository;
    featureFlags = agentActionUseCaseFeatureFlags;
  });

  group('agent action trigger use cases', () {
    setUp(() {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
    });

    test('should reject trigger save when maintenance mode is enabled', () async {
      await featureFlags.setEnableAgentActionsMaintenanceMode(true);
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-maint',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect((result.exceptionOrNull()! as ActionValidationFailure).code, AgentActionFailureCode.maintenanceMode);
    });

    test('should save valid app start trigger for an existing action', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      final saved = repository.triggers['trigger-1'];
      expect(saved, isNotNull);
      expect(saved!.id, trigger.id);
      expect(saved.actionId, trigger.actionId);
      expect(saved.type, trigger.type);
    });

    test('should trim trigger id and action id when saving trigger', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: '  trigger-spaced  ',
        actionId: '  action-1  ',
        type: AgentActionTriggerType.manual,
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'trigger-spaced');
      expect(result.getOrThrow().actionId, 'action-1');
      expect(repository.triggers['trigger-spaced'], isNotNull);
      expect(repository.triggers['trigger-spaced']!.actionId, 'action-1');
      expect(repository.triggers.containsKey('  trigger-spaced  '), isFalse);
    });

    test('should reject app-close trigger when action is approved for remote execution', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Remote ready',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
          ),
        ),
      );
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should reject app-close trigger when action requires elevated execution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Elevated command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
        ),
      );
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should save app-close trigger when remote policy requires reapproval', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Remote stale',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
            requiresReapproval: true,
          ),
        ),
      );
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      final saved = repository.triggers['trigger-1'];
      expect(saved, isNotNull);
      expect(saved!.id, trigger.id);
      expect(saved.actionId, trigger.actionId);
      expect(saved.type, trigger.type);
    });

    test('should save temporal interval trigger with positive interval', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.interval,
        schedule: AgentActionTriggerSchedule(
          interval: Duration(minutes: 15),
        ),
      );

      final result = await useCase(trigger);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().schedule.interval, const Duration(minutes: 15));
    });

    test('should reject invalid weekly trigger before saving', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.weekly,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 8 * 60,
          weekdays: {0},
        ),
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should return not found when trigger references missing action', () async {
      final useCase = SaveAgentActionTrigger(
        repository,
        const ValidateAgentActionTrigger(),
        featureFlags,
      );
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'missing-action',
        type: AgentActionTriggerType.appClose,
      );

      final result = await useCase(trigger);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
      expect(repository.triggers, isEmpty);
    });

    test('should get, list and delete triggers through repository', () async {
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 9 * 60,
        ),
      );
      repository.triggers[trigger.id] = trigger;

      final getResult = await GetAgentActionTrigger(repository)('trigger-1');
      final listResult = await ListAgentActionTriggers(repository)(
        actionId: 'action-1',
        isEnabled: true,
        types: {AgentActionTriggerType.daily},
      );
      final deleteResult = await DeleteAgentActionTrigger(repository)('trigger-1');

      expect(getResult.getOrThrow(), trigger);
      expect(listResult.getOrThrow(), [trigger]);
      expect(deleteResult.isSuccess(), isTrue);
      expect(repository.triggers, isEmpty);
    });

    test('should reject delete trigger with blank id', () async {
      final result = await DeleteAgentActionTrigger(repository)('   ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should return not found when deleting missing trigger', () async {
      final result = await DeleteAgentActionTrigger(repository)('missing-trigger');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionNotFoundFailure>());
    });

    test('should reject get trigger with blank id', () async {
      final result = await GetAgentActionTrigger(repository)('');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim id when getting trigger', () async {
      const trigger = AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.manual,
      );
      repository.triggers[trigger.id] = trigger;

      final result = await GetAgentActionTrigger(repository)(' trigger-1 ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().id, 'trigger-1');
    });

    test('should reject list triggers with blank action id filter', () async {
      final result = await ListAgentActionTriggers(repository)(actionId: '  ');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
    });

    test('should trim action id when listing triggers', () async {
      repository.triggers['t1'] = const AgentActionTrigger(
        id: 't1',
        actionId: 'action-1',
        type: AgentActionTriggerType.manual,
      );

      final result = await ListAgentActionTriggers(repository)(actionId: '  action-1  ');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), hasLength(1));
    });

    test('should dispatch temporal trigger through local action runner with trigger metadata', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 9 * 60,
        ),
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'trigger-1',
        scheduledAt: DateTime.utc(2026, 5, 15, 13),
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.source, AgentActionRequestSource.scheduler);
      expect(execution.triggerId, 'trigger-1');
      expect(execution.triggerType, AgentActionTriggerType.daily);
      expect(execution.scheduledAt, DateTime.utc(2026, 5, 15, 13));
      expect(execution.triggeredAt, DateTime(2026, 5, 15, 9));
      expect(execution.idempotencyKey, 'trigger:trigger-1:2026-05-15T13:00:00.000Z');
    });

    test('should trim trigger action id when dispatching temporal trigger', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: '  action-1  ',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(
          timeOfDayMinutes: 9 * 60,
        ),
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'trigger-1',
        scheduledAt: DateTime.utc(2026, 5, 15, 13),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().actionId, 'action-1');
    });

    test('should reject dispatch when trigger action id is only whitespace', () async {
      repository.triggers['bad-trigger'] = const AgentActionTrigger(
        id: 'bad-trigger',
        actionId: '   ',
        type: AgentActionTriggerType.manual,
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(repository, runUseCase);

      final result = await dispatchUseCase(triggerId: 'bad-trigger');

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ActionValidationFailure>());
      expect((failure! as ActionValidationFailure).code, AgentActionFailureCode.triggerActionIdBlank);
    });

    test('should dispatch remote trigger through the same local action runner flow', () async {
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
      repository.triggers['remote-trigger'] = const AgentActionTrigger(
        id: 'remote-trigger',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'remote-trigger',
        idempotencyKey: 'remote-key-1',
        requestedBy: 'hub:user-1',
        traceId: 'trace-1',
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.source, AgentActionRequestSource.remoteHub);
      expect(execution.triggerId, 'remote-trigger');
      expect(execution.triggerType, AgentActionTriggerType.remote);
      expect(execution.requestedBy, 'hub:user-1');
      expect(execution.traceId, 'trace-1');
      expect(execution.idempotencyKey, 'remote-key-1');
      expect(repository.savedExecutions.map((item) => item.status), [
        AgentActionExecutionStatus.queued,
        AgentActionExecutionStatus.running,
        AgentActionExecutionStatus.succeeded,
      ]);
    });

    test('should trim optional metadata when dispatching remote trigger', () async {
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
      repository.triggers['remote-trigger'] = const AgentActionTrigger(
        id: 'remote-trigger',
        actionId: 'action-1',
        type: AgentActionTriggerType.remote,
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableRemoteAgentActions(true);
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Success(
              AgentActionProcessResult(
                status: AgentActionExecutionStatus.succeeded,
                pid: 1234,
                exitCode: 0,
                processStartedAt: DateTime(2026, 5, 15, 9),
                finishedAt: DateTime(2026, 5, 15, 9, 1),
                stdout: AgentActionCapturedOutput.disabled,
                stderr: AgentActionCapturedOutput.disabled,
                redactionApplied: true,
              ),
            ),
          ),
        ]),
        const Uuid(),
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8, 59),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(
        repository,
        runUseCase,
        now: () => DateTime(2026, 5, 15, 9),
      );

      final result = await dispatchUseCase(
        triggerId: 'remote-trigger',
        idempotencyKey: '  remote-key-trimmed  ',
        requestedBy: '  hub:user-1  ',
        traceId: '  trace-99  ',
      );

      expect(result.isSuccess(), isTrue);
      final execution = result.getOrThrow();
      expect(execution.requestedBy, 'hub:user-1');
      expect(execution.traceId, 'trace-99');
      expect(execution.idempotencyKey, 'remote-key-trimmed');
    });

    test('should reject dispatch when trigger is disabled', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
        isEnabled: false,
      );
      final runUseCase = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([
          FakeAgentActionLocalRunner(
            result: Failure(ActionRuntimeFailure('Should not run')),
          ),
        ]),
        const Uuid(),
      );
      final dispatchUseCase = DispatchAgentActionTrigger(repository, runUseCase);

      final result = await dispatchUseCase(triggerId: 'trigger-1');

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionValidationFailure>());
      expect(repository.savedExecutions, isEmpty);
    });
  });
}
