import 'package:plug_agente/application/actions/action_trigger_schedule_calculator.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_portable_codec.dart';

import '../../helpers/agent_action_use_case_test_support.dart';

const _config = ExecutableActionConfig(executablePath: AgentActionPathReference(originalPath: r'C:\tools\job.exe'));

class _Runner extends FakeAgentActionLocalRunner {
  _Runner(this.now) : super(actionType: AgentActionType.executable, result: Failure(ActionRuntimeFailure('Unused')));
  final DateTime Function() now;
  final definitions = <AgentActionDefinition>[];
  Future<Result<AgentActionProcessResult>> Function()? handler;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    definitions.add(definition);
    if (handler != null) return handler!();
    return Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        processStartedAt: now(),
        finishedAt: now(),
        pid: 1234,
        exitCode: 0,
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    );
  }
}

class _Timer implements AgentActionSchedulerTimer {
  _Timer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
}

void main() {
  late FakeAgentActionRepository repository;
  late DateTime now;
  late _Runner runner;
  late RunAgentActionLocally run;
  late AgentActionTriggerScheduler scheduler;
  late List<_Timer> timers;

  setUp(() {
    setUpAgentActionUseCaseTests();
    repository = FakeAgentActionRepository();
    now = DateTime(2026, 10, 3, 12);
    runner = _Runner(() => now);
    timers = [];
    for (final id in ['a', 'b', 'c']) {
      repository.definitions[id] = AgentActionDefinition(
        id: id,
        name: id,
        state: AgentActionState.active,
        config: _config,
      );
    }
    run = RunAgentActionLocally(repository, AgentActionLocalRunnerRegistry([runner]), const Uuid(), now: () => now);
    scheduler = AgentActionTriggerScheduler(
      repository,
      DispatchAgentActionTrigger(repository, run),
      now: () => now,
      timerFactory: (delay, callback) {
        final timer = _Timer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
  });
  tearDown(() => scheduler.stop());

  AgentActionExecution event(AgentActionExecutionStatus status) => AgentActionExecution(
    id: 'source-execution',
    actionId: 'a',
    actionType: AgentActionType.executable,
    status: status,
    requestedAt: now,
    source: AgentActionRequestSource.localUi,
    redactionApplied: true,
  );

  test('interval without start date retains its anchor after dispatch and restart', () async {
    repository.triggers['interval'] = const AgentActionTrigger(
      id: 'interval',
      actionId: 'a',
      type: AgentActionTriggerType.interval,
      schedule: AgentActionTriggerSchedule(interval: Duration(minutes: 10)),
    );
    await scheduler.start();
    expect(timers.single.delay, Duration.zero);
    timers.single.callback();
    await Future<void>.delayed(Duration.zero);
    expect(runner.definitions, hasLength(1));
    expect(timers.last.delay, const Duration(minutes: 10));
    expect(repository.triggers['interval']!.schedule.startAt, now);
    scheduler.stop();
    now = now.add(const Duration(minutes: 3));
    await scheduler.start();
    expect(timers.last.delay, const Duration(minutes: 7));
  });

  test('calculator uses the last scheduled slot when an interval has no persisted start date', () {
    final result = const AgentActionTriggerScheduleCalculator().nextRun(
      trigger: AgentActionTrigger(
        id: 'i',
        actionId: 'a',
        type: AgentActionTriggerType.interval,
        lastScheduledAt: now,
        schedule: const AgentActionTriggerSchedule(interval: Duration(minutes: 10)),
      ),
      now: now.add(const Duration(seconds: 2)),
    );
    expect(result.getOrThrow().nextRunAt, now.add(const Duration(minutes: 10)));
  });

  for (final status in [
    AgentActionExecutionStatus.succeeded,
    AgentActionExecutionStatus.failed,
    AgentActionExecutionStatus.timedOut,
  ]) {
    test('execution event dispatch matches $status and does not replay a completed source', () async {
      repository.triggers['success'] = const AgentActionTrigger(
        id: 'success',
        actionId: 'b',
        type: AgentActionTriggerType.actionSucceeded,
        schedule: AgentActionTriggerSchedule(sourceActionId: 'a'),
      );
      repository.triggers['failure'] = const AgentActionTrigger(
        id: 'failure',
        actionId: 'c',
        type: AgentActionTriggerType.actionFailed,
        schedule: AgentActionTriggerSchedule(sourceActionId: 'a'),
      );
      await scheduler.start();
      expect((await scheduler.dispatchExecutionTriggers(event(status))).getOrThrow(), 1);
      expect(runner.definitions.single.id, status.isSuccess ? 'b' : 'c');
      await scheduler.dispatchExecutionTriggers(event(status));
      expect(runner.definitions, hasLength(1));
    });
  }

  test('disabled event trigger and stopped scheduler do not dispatch', () async {
    repository.triggers['event'] = const AgentActionTrigger(
      id: 'event',
      actionId: 'b',
      isEnabled: false,
      type: AgentActionTriggerType.actionSucceeded,
      schedule: AgentActionTriggerSchedule(sourceActionId: 'a'),
    );
    await scheduler.start();
    expect((await scheduler.dispatchExecutionTriggers(event(AgentActionExecutionStatus.succeeded))).getOrThrow(), 0);
    scheduler.stop();
    repository.triggers['event'] = repository.triggers['event']!.copyWith(isEnabled: true);
    expect((await scheduler.dispatchExecutionTriggers(event(AgentActionExecutionStatus.succeeded))).getOrThrow(), 0);
    expect(runner.definitions, isEmpty);
  });

  test('maintenance blocks execution event dispatch', () async {
    repository.triggers['event'] = const AgentActionTrigger(
      id: 'event',
      actionId: 'b',
      type: AgentActionTriggerType.actionSucceeded,
      schedule: AgentActionTriggerSchedule(sourceActionId: 'a'),
    );
    scheduler = AgentActionTriggerScheduler(
      repository,
      DispatchAgentActionTrigger(repository, run),
      featureFlags: agentActionUseCaseFeatureFlags,
    );
    await scheduler.start();
    await agentActionUseCaseFeatureFlags.setEnableAgentActionsMaintenanceMode(true);
    final result = await scheduler.dispatchExecutionTriggers(event(AgentActionExecutionStatus.succeeded));
    expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
    expect(runner.definitions, isEmpty);
  });

  test('command line only accepts manual triggers and app-close rejects unbounded policies', () async {
    final save = SaveAgentActionTrigger(repository, const ValidateAgentActionTrigger(), agentActionUseCaseFeatureFlags);
    repository.definitions['a'] = repository.definitions['a']!.copyWith(
      config: const CommandLineActionConfig(command: 'echo hello'),
    );
    final rejected = await save(
      const AgentActionTrigger(id: 'auto', actionId: 'a', type: AgentActionTriggerType.appStart),
    );
    expect((rejected.exceptionOrNull()! as ActionFailure).code, AgentActionFailureCode.commandLineLocalOnly);
    expect(
      (await save(
        const AgentActionTrigger(id: 'manual', actionId: 'a', type: AgentActionTriggerType.manual),
      )).isSuccess(),
      isTrue,
    );
    for (final timeout in [
      const AgentActionTimeoutPolicy(),
      const AgentActionTimeoutPolicy(maxRuntime: Duration(seconds: 5), killMainProcessOnTimeout: false),
    ]) {
      repository.definitions['a'] = repository.definitions['a']!.copyWith(
        config: _config,
        policies: AgentActionDefinitionPolicies(timeout: timeout),
      );
      final result = await save(
        const AgentActionTrigger(id: 'close', actionId: 'a', type: AgentActionTriggerType.appClose),
      );
      expect((result.exceptionOrNull()! as ActionFailure).code, AgentActionFailureCode.appCloseRuntimeTooLong);
    }
    expect(repository.triggers, isNot(contains('close')));
  });

  test('event dependencies reject indirect cycles and protect source deletion', () async {
    final save = SaveAgentActionTrigger(repository, const ValidateAgentActionTrigger(), agentActionUseCaseFeatureFlags);
    final first = await save(
      const AgentActionTrigger(
        id: 'ab',
        actionId: 'b',
        type: AgentActionTriggerType.actionSucceeded,
        schedule: AgentActionTriggerSchedule(sourceActionId: 'a'),
      ),
    );
    expect(first.isSuccess(), isTrue);
    final second = await save(
      const AgentActionTrigger(
        id: 'bc',
        actionId: 'c',
        type: AgentActionTriggerType.actionFailed,
        schedule: AgentActionTriggerSchedule(sourceActionId: 'b'),
      ),
    );
    expect(second.isSuccess(), isTrue);
    final cycle = await save(
      const AgentActionTrigger(
        id: 'ca',
        actionId: 'a',
        type: AgentActionTriggerType.actionSucceeded,
        schedule: AgentActionTriggerSchedule(sourceActionId: 'c'),
      ),
    );
    expect((cycle.exceptionOrNull()! as ActionValidationFailure).context['reason'], 'event_trigger_cycle');
    final deletion = await DeleteAgentActionDefinition(repository)('a');
    expect((deletion.exceptionOrNull()! as ActionValidationFailure).context['reason'], 'action_has_event_dependents');
    expect(repository.definitions, contains('a'));
  });

  test('saving completion emits one event only after a successful terminal transition', () async {
    var notifications = 0;
    final save = SaveAgentActionExecution(
      repository,
      onTerminalExecution: (_) async {
        notifications++;
      },
    );
    await save(event(AgentActionExecutionStatus.running));
    expect(notifications, 0);
    await save(event(AgentActionExecutionStatus.succeeded));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
    await save(event(AgentActionExecutionStatus.succeeded));
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
  });

  test('scheduled stop bounds process runtime and prevents retry after the cutoff', () async {
    now = DateTime(2026, 10, 3, 11, 59, 58);
    repository.definitions['a'] = repository.definitions['a']!.copyWith(
      policies: const AgentActionDefinitionPolicies(
        timeout: AgentActionTimeoutPolicy(stopTimeOfDayMinutes: 720),
        retry: AgentActionRetryPolicy(maxAttempts: 3),
      ),
    );
    runner.handler = () async {
      now = now.add(const Duration(seconds: 2));
      return Success(
        AgentActionProcessResult(
          status: AgentActionExecutionStatus.timedOut,
          pid: 1234,
          processStartedAt: now.subtract(const Duration(seconds: 2)),
          finishedAt: now,
          stdout: AgentActionCapturedOutput.disabled,
          stderr: AgentActionCapturedOutput.disabled,
          timedOut: true,
          killed: true,
          redactionApplied: true,
        ),
      );
    };
    final result = await run(
      const AgentActionExecutionRequest(actionId: 'a', source: AgentActionRequestSource.localUi),
    );
    expect(result.getOrThrow().status, AgentActionExecutionStatus.timedOut);
    expect(runner.definitions, hasLength(1));
    expect(runner.definitions.single.policies.timeout.maxRuntime, const Duration(seconds: 2));
    expect(runner.definitions.single.policies.timeout.executionDeadline, now);
  });

  test('stop deadline uses the next local day when the configured time has passed', () {
    const policy = AgentActionTimeoutPolicy(maxRuntime: Duration(days: 2), stopTimeOfDayMinutes: 720);
    expect(policy.deadlineFrom(DateTime(2026, 10, 3, 13)), DateTime(2026, 10, 4, 12));
    expect(policy.nextStopAt(DateTime(2026, 10, 3, 12)), DateTime(2026, 10, 3, 12));
  });

  test('new event and stop settings survive portable export and import', () {
    const codec = AgentActionPortableCodec();
    final definition = repository.definitions['a']!.copyWith(
      policies: const AgentActionDefinitionPolicies(timeout: AgentActionTimeoutPolicy(stopTimeOfDayMinutes: 1080)),
    );
    final decoded = codec.definitionFromPortableJson(codec.definitionToPortableJson(definition));
    expect(decoded.policies.timeout.stopTimeOfDayMinutes, 1080);
    const trigger = AgentActionTrigger(
      id: 'event',
      actionId: 'b',
      type: AgentActionTriggerType.actionFailed,
      schedule: AgentActionTriggerSchedule(sourceActionId: 'a'),
    );
    final restored = codec.triggerFromPortableJson(codec.triggerToPortableJson(trigger));
    expect(restored.type, trigger.type);
    expect(restored.schedule.sourceActionId, 'a');
  });
}
