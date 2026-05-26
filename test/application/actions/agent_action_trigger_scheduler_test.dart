import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_scheduler_instance_lock.dart';
import 'package:result_dart/result_dart.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

class _HeldSchedulerInstanceLock implements IAgentActionSchedulerInstanceLock {
  @override
  bool get isHeld => true;

  @override
  Future<Result<Unit>> tryAcquire() async {
    return Failure(
      ActionAuthorizationFailure.withContext(
        message: 'Scheduler lock is held.',
        code: AgentActionFailureCode.schedulerBootstrapFailed,
        context: const {
          'reason': AgentActionTriggerConstants.schedulerInstanceLockedReason,
        },
      ),
    );
  }

  @override
  Future<void> release() async {}
}

class FakeAgentActionRepository implements IAgentActionRepository {
  final Map<String, AgentActionDefinition> definitions = <String, AgentActionDefinition>{};
  final Map<String, AgentActionTrigger> triggers = <String, AgentActionTrigger>{};
  final Map<String, AgentActionExecution> executions = <String, AgentActionExecution>{};
  bool failListTriggers = false;

  @override
  Future<Result<AgentActionDefinition>> saveDefinition(
    AgentActionDefinition definition,
  ) async {
    definitions[definition.id] = definition;
    return Success(definition);
  }

  @override
  Future<Result<AgentActionDefinition>> getDefinition(String id) async {
    final definition = definitions[id];
    if (definition == null) {
      return Failure(ActionNotFoundFailure('Action definition was not found.'));
    }

    return Success(definition);
  }

  @override
  Future<Result<List<AgentActionDefinition>>> listDefinitions() async {
    return Success(definitions.values.toList(growable: false));
  }

  @override
  Future<Result<void>> deleteDefinition(String id) async {
    definitions.remove(id);
    triggers.removeWhere((_, AgentActionTrigger trigger) => trigger.actionId == id);
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionTrigger>> saveTrigger(
    AgentActionTrigger trigger,
  ) async {
    triggers[trigger.id] = trigger;
    return Success(trigger);
  }

  @override
  Future<Result<AgentActionTrigger>> getTrigger(String id) async {
    final trigger = triggers[id];
    if (trigger == null) {
      return Failure(ActionNotFoundFailure('Action trigger was not found.'));
    }

    return Success(trigger);
  }

  @override
  Future<Result<List<AgentActionTrigger>>> listTriggers({
    String? actionId,
    bool? isEnabled,
    Set<AgentActionTriggerType>? types,
  }) async {
    if (failListTriggers) {
      return Failure(
        ActionFailure.withContext(
          message: 'Failed to list triggers.',
          context: const {'operation': 'listTriggers'},
        ),
      );
    }

    final filtered = triggers.values
        .where((trigger) {
          final matchesAction = actionId == null || trigger.actionId == actionId;
          final matchesEnabled = isEnabled == null || trigger.isEnabled == isEnabled;
          final matchesType = types == null || types.isEmpty || types.contains(trigger.type);
          return matchesAction && matchesEnabled && matchesType;
        })
        .toList(growable: false);

    return Success(filtered);
  }

  @override
  Future<Result<void>> deleteTrigger(String id) async {
    triggers.remove(id);
    return const Success(unit);
  }

  @override
  Future<Result<AgentActionExecution>> saveExecution(
    AgentActionExecution execution,
  ) async {
    executions[execution.id] = execution;
    return Success(execution);
  }

  @override
  Future<Result<AgentActionExecution>> getExecution(
    String id, {
    bool hydrateCapturedOutput = true,
  }) async {
    final execution = executions[id];
    if (execution == null) {
      return Failure(ActionNotFoundFailure('Action execution was not found.'));
    }

    return Success(execution);
  }

  @override
  Future<Result<CapturedOutputUtf8Window>> sliceCapturedOutput({
    required String executionId,
    required String stream,
    required int offsetUtf8,
    required int maxBytes,
  }) async => Success(
    (
      text: '',
      nextOffset: offsetUtf8,
      totalBytes: 0,
      responseTruncated: false,
      effectiveStart: offsetUtf8,
    ),
  );

  @override
  Future<Result<List<AgentActionExecution>>> listExecutions({
    String? actionId,
    String? idempotencyKey,
    Set<AgentActionExecutionStatus>? statuses,
    DateTime? requestedAfter,
    int? limit,
  }) async {
    final filtered = executions.values
        .where((execution) {
          final matchesAction = actionId == null || execution.actionId == actionId;
          final matchesIdempotencyKey = idempotencyKey == null || execution.idempotencyKey == idempotencyKey;
          final matchesStatus = statuses == null || statuses.isEmpty || statuses.contains(execution.status);
          final matchesRequestedAfter = requestedAfter == null || !execution.requestedAt.isBefore(requestedAfter);
          return matchesAction && matchesIdempotencyKey && matchesStatus && matchesRequestedAfter;
        })
        .toList(growable: false);

    return Success(limit == null ? filtered : filtered.take(limit).toList(growable: false));
  }

  @override
  Future<Result<int>> cleanupExecutions({
    required DateTime olderThan,
  }) async {
    final before = executions.length;
    executions.removeWhere((_, execution) {
      final finishedAt = execution.finishedAt;
      return finishedAt != null && finishedAt.isBefore(olderThan);
    });
    return Success(before - executions.length);
  }

  @override
  Future<Result<int>> clearCapturedOutputOlderThan({
    required DateTime olderThan,
  }) async {
    var cleared = 0;
    for (final entry in executions.entries.toList()) {
      final execution = entry.value;
      if (!execution.status.isTerminal) {
        continue;
      }
      final finishedAt = execution.finishedAt;
      final requestedAt = execution.requestedAt;
      final isOld =
          (finishedAt != null && finishedAt.isBefore(olderThan)) ||
          (finishedAt == null && requestedAt.isBefore(olderThan));
      if (!isOld) {
        continue;
      }
      if (execution.stdoutText == null && execution.stderrText == null) {
        continue;
      }
      executions[entry.key] = AgentActionExecution(
        id: execution.id,
        actionId: execution.actionId,
        actionType: execution.actionType,
        status: execution.status,
        requestedAt: execution.requestedAt,
        source: execution.source,
        idempotencyKey: execution.idempotencyKey,
        requestedBy: execution.requestedBy,
        traceId: execution.traceId,
        runtimeInstanceId: execution.runtimeInstanceId,
        runtimeSessionId: execution.runtimeSessionId,
        triggerId: execution.triggerId,
        triggerType: execution.triggerType,
        scheduledAt: execution.scheduledAt,
        triggeredAt: execution.triggeredAt,
        queueStartedAt: execution.queueStartedAt,
        processStartedAt: execution.processStartedAt,
        finishedAt: execution.finishedAt,
        timeoutAt: execution.timeoutAt,
        pid: execution.pid,
        exitCode: execution.exitCode,
        processExecutable: execution.processExecutable,
        processArgumentCount: execution.processArgumentCount,
        processCommandPreview: execution.processCommandPreview,
        definitionSnapshotHash: execution.definitionSnapshotHash,
        contextHash: execution.contextHash,
        redactionApplied: execution.redactionApplied,
        failureCode: execution.failureCode,
        failurePhase: execution.failurePhase,
        failureMessage: execution.failureMessage,
      );
      cleared++;
    }
    return Success(cleared);
  }
}

class FakeAgentActionLocalRunner implements AgentActionLocalRunner {
  FakeAgentActionLocalRunner({
    Future<Result<AgentActionProcessResult>> Function()? runHandler,
  }) : _runHandler = runHandler;

  final Future<Result<AgentActionProcessResult>> Function()? _runHandler;
  int runCount = 0;

  @override
  AgentActionType get type => AgentActionType.commandLine;

  @override
  Future<Result<AgentActionProcessResult>> run({
    required String executionId,
    required AgentActionDefinition definition,
    required AgentActionExecutionRequest request,
  }) async {
    runCount += 1;
    final handler = _runHandler;
    if (handler != null) {
      return handler();
    }

    return Success(
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
    );
  }

  @override
  Future<Result<AgentActionCancellationResult>> cancel({
    required String executionId,
    int? expectedPid,
    String? expectedProcessExecutable,
    DateTime? expectedProcessStartedAt,
  }) async {
    return Success(
      AgentActionCancellationResult(
        executionId: executionId,
        status: AgentActionExecutionStatus.killed,
        killed: true,
      ),
    );
  }
}

class FakeSchedulerTimer implements AgentActionSchedulerTimer {
  FakeSchedulerTimer(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void fire() {
    if (!cancelled) {
      callback();
    }
  }

  @override
  void cancel() {
    cancelled = true;
  }
}

void main() {
  setUpAll(ensureIanaTimeZoneDataLoaded);

  group('AgentActionTriggerScheduleCalculator', () {
    const calculator = AgentActionTriggerScheduleCalculator();

    test('should ignore one-time trigger missed while app was closed', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.once,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
          ),
        ),
        now: DateTime(2026, 5, 15, 9),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().nextRunAt, isNull);
    });

    test('should calculate next interval from original anchor', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.interval,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
            interval: const Duration(minutes: 15),
          ),
        ),
        now: DateTime(2026, 5, 15, 8, 37),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 15, 8, 45));
    });

    test('should calculate next daily trigger time', () {
      final result = calculator.nextRun(
        trigger: const AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.daily,
          schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
        ),
        now: DateTime(2026, 5, 15, 9, 1),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 16, 9));
    });

    test('should calculate next weekly trigger time', () {
      final result = calculator.nextRun(
        trigger: const AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.weekly,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 10 * 60,
            weekdays: {DateTime.monday},
          ),
        ),
        now: DateTime(2026, 5, 15, 9),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 18, 10));
    });

    test('should skip invalid monthly day until a valid month exists', () {
      final result = calculator.nextRun(
        trigger: const AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.monthly,
          schedule: AgentActionTriggerSchedule(
            dayOfMonth: 31,
            timeOfDayMinutes: 7 * 60,
          ),
        ),
        now: DateTime(2026, 4, 30, 8),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 31, 7));
    });

    test('should calculate next daily trigger in IANA timezone', () {
      final result = calculator.nextRun(
        trigger: const AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.daily,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            timezoneId: 'America/New_York',
          ),
        ),
        now: DateTime.utc(2026, 5, 16, 14, 5),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().nextRunAt!.toUtc(), DateTime.utc(2026, 5, 17, 13));
    });

    test(
      'should map daily 02:30 America/New_York on spring-forward day to TZDateTime normalization',
      () {
        final loc = tz.getLocation('America/New_York');
        final now = tz.TZDateTime(loc, 2024, 3, 9, 20).toUtc();

        final result = calculator.nextRun(
          trigger: const AgentActionTrigger(
            id: 'trigger-1',
            actionId: 'action-1',
            type: AgentActionTriggerType.daily,
            schedule: AgentActionTriggerSchedule(
              timeOfDayMinutes: 2 * Duration.minutesPerHour + 30,
              timezoneId: 'America/New_York',
            ),
          ),
          now: now,
        );

        expect(result.isSuccess(), isTrue);
        expect(
          result.getOrThrow().nextRunAt!.toUtc(),
          DateTime.utc(2024, 3, 10, 7, 30),
        );
      },
    );

    test('should advance daily 01:30 America/New_York to next calendar day when now is in fold window', () {
      final now = DateTime.utc(2024, 11, 3, 6, 45);

      final result = calculator.nextRun(
        trigger: const AgentActionTrigger(
          id: 'trigger-1',
          actionId: 'action-1',
          type: AgentActionTriggerType.daily,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: Duration.minutesPerHour + 30,
            timezoneId: 'America/New_York',
          ),
        ),
        now: now,
      );

      expect(result.isSuccess(), isTrue);
      expect(
        result.getOrThrow().nextRunAt!.toUtc(),
        DateTime.utc(2024, 11, 4, 6, 30),
      );
    });

    test('should treat fall-back duplicate 01:30 wall times as two distinct instants', () {
      final loc = tz.getLocation('America/New_York');
      final first = tz.TZDateTime(loc, 2024, 11, 3, 1, 30);
      final second = first.add(const Duration(hours: 1));

      expect(first.toUtc(), DateTime.utc(2024, 11, 3, 5, 30));
      expect(second.toUtc(), DateTime.utc(2024, 11, 3, 6, 30));
      expect(first.isBefore(second), isTrue);
    });
  });

  group('AgentActionTriggerScheduler', () {
    late FakeAgentActionRepository repository;
    late FakeAgentActionLocalRunner runner;
    late List<FakeSchedulerTimer> timers;

    setUp(() {
      repository = FakeAgentActionRepository();
      runner = FakeAgentActionLocalRunner();
      timers = <FakeSchedulerTimer>[];
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
      );
    });

    AgentActionTriggerScheduler createScheduler({
      FeatureFlags? featureFlags,
      DateTime Function()? now,
      IAgentActionSchedulerInstanceLock? schedulerInstanceLock,
    }) {
      final runAction = RunAgentActionLocally(
        repository,
        AgentActionLocalRunnerRegistry([runner]),
        const Uuid(),
        featureFlags: featureFlags,
        now: now,
      );
      final dispatchTrigger = DispatchAgentActionTrigger(
        repository,
        runAction,
        now: now,
      );
      return AgentActionTriggerScheduler(
        repository,
        dispatchTrigger,
        timerFactory: (delay, callback) {
          final timer = FakeSchedulerTimer(delay, callback);
          timers.add(timer);
          return timer;
        },
        featureFlags: featureFlags,
        schedulerInstanceLock: schedulerInstanceLock,
        now: now,
      );
    }

    test('should not start scheduler when instance lock is already held', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );
      final scheduler = createScheduler(
        schedulerInstanceLock: _HeldSchedulerInstanceLock(),
        now: () => DateTime(2026, 5, 15, 8),
      );

      final result = await scheduler.start();

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionAuthorizationFailure;
      expect(failure.code, AgentActionFailureCode.schedulerBootstrapFailed);
      expect(
        failure.context['reason'],
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );
      expect(timers, isEmpty);
      expect(scheduler.isBootstrapDisabled, isFalse);
      expect(
        scheduler.lastStartIssueReason,
        AgentActionTriggerConstants.schedulerInstanceLockedReason,
      );
    });

    test('should schedule enabled temporal triggers and persist next run', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 8),
      );

      final result = await scheduler.start();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().scheduledCount, 1);
      expect(timers.single.delay, const Duration(hours: 1));
      expect(repository.triggers['trigger-1']?.nextRunAt, DateTime(2026, 5, 15, 9));
    });

    test('should not start scheduler when agent actions feature flag is disabled', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActions(false);
      final scheduler = createScheduler(
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8),
      );

      final result = await scheduler.start();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(timers, isEmpty);
      expect(repository.triggers['trigger-1']?.nextRunAt, isNull);
    });

    test('should disable scheduler when bootstrap cannot list triggers', () async {
      repository.failListTriggers = true;
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 8),
      );

      final startResult = await scheduler.start();

      expect(startResult.isError(), isTrue);
      expect((startResult.exceptionOrNull()! as ActionFailure).message, contains('list triggers'));
      expect(scheduler.isBootstrapDisabled, isTrue);
      expect(timers, isEmpty);

      final retryResult = await scheduler.start();
      expect(retryResult.isError(), isTrue);
      expect(
        (retryResult.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.schedulerBootstrapFailed,
      );

      final appStartResult = await scheduler.dispatchAppStartTriggers();
      expect(appStartResult.isError(), isTrue);
      expect(
        (appStartResult.exceptionOrNull()! as ActionAuthorizationFailure).code,
        AgentActionFailureCode.schedulerBootstrapFailed,
      );
    });

    test('should not start scheduler while maintenance mode is enabled', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final scheduler = createScheduler(
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8),
      );

      final result = await scheduler.start();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(timers, isEmpty);
      expect(repository.triggers['trigger-1']?.nextRunAt, isNull);
    });

    test('should dispatch scheduled trigger when timer fires', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.daily,
        schedule: AgentActionTriggerSchedule(timeOfDayMinutes: 9 * 60),
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 8),
      );
      await scheduler.start();

      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(runner.runCount, 1);
      expect(repository.executions.values.last.triggerId, 'trigger-1');
      expect(repository.executions.values.last.source, AgentActionRequestSource.scheduler);
    });

    test('should not dispatch app-start lifecycle triggers while maintenance mode is enabled', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final scheduler = createScheduler(
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 8),
      );

      final result = await scheduler.dispatchAppStartTriggers();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(runner.runCount, 0);
    });

    test('should not dispatch app-close lifecycle triggers while maintenance mode is enabled', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          timeout: AgentActionTimeoutPolicy(
            maxRuntime: Duration(seconds: 1),
          ),
        ),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final flags = FeatureFlags(InMemoryAppSettingsStore());
      await flags.setEnableAgentActionsMaintenanceMode(true);
      final scheduler = createScheduler(
        featureFlags: flags,
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<ActionAuthorizationFailure>());
      expect(runner.runCount, 0);
    });

    test('should dispatch app-start lifecycle triggers on demand', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appStart,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 8),
      );

      final result = await scheduler.dispatchAppStartTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 1);
      expect(runner.runCount, 1);
      expect(repository.triggers['trigger-1']?.lastRunAt, DateTime(2026, 5, 15, 8));
    });

    test('should dispatch app-close lifecycle triggers on demand', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          timeout: AgentActionTimeoutPolicy(
            maxRuntime: Duration(seconds: 1),
          ),
        ),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 1);
      expect(runner.runCount, 1);
      expect(repository.triggers['trigger-1']?.lastRunAt, DateTime(2026, 5, 15, 18));
    });

    test('should skip app-close trigger when action id is only whitespace', () async {
      repository.triggers['trigger-bad'] = const AgentActionTrigger(
        id: 'trigger-bad',
        actionId: '   ',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 0);
      expect(runner.runCount, 0);
    });

    test('should trim action id when validating app-close shutdown budget', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          timeout: AgentActionTimeoutPolicy(
            maxRuntime: Duration(seconds: 1),
          ),
        ),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: '  action-1  ',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 1);
      expect(runner.runCount, 1);
    });

    test('should skip app-close trigger when action requires elevated execution', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Elevated command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          elevated: AgentActionElevatedPolicy(runElevated: true),
          timeout: AgentActionTimeoutPolicy(
            maxRuntime: Duration(seconds: 1),
          ),
        ),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 0);
      expect(runner.runCount, 0);
      expect(repository.triggers['trigger-1']?.lastRunAt, isNull);
    });

    test('should skip app-close trigger when action is approved for remote execution', () async {
      repository.definitions['action-1'] = AgentActionDefinition(
        id: 'action-1',
        name: 'Remote-ready',
        state: AgentActionState.active,
        config: const CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          remote: AgentActionRemotePolicy(
            isEnabled: true,
            approvedAt: DateTime.utc(2026),
          ),
          timeout: const AgentActionTimeoutPolicy(
            maxRuntime: Duration(seconds: 1),
          ),
        ),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 0);
      expect(runner.runCount, 0);
      expect(repository.triggers['trigger-1']?.lastRunAt, isNull);
    });

    test('should dispatch app-close when remote policy requires reapproval', () async {
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
          timeout: const AgentActionTimeoutPolicy(
            maxRuntime: Duration(seconds: 1),
          ),
        ),
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 1);
      expect(runner.runCount, 1);
    });

    test('should skip app-close trigger when action runtime exceeds shutdown budget', () async {
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 0);
      expect(runner.runCount, 0);
      expect(repository.triggers['trigger-1']?.lastRunAt, isNull);
    });

    test('should not block app-close indefinitely when a trigger times out', () async {
      repository.definitions['action-1'] = const AgentActionDefinition(
        id: 'action-1',
        name: 'Run command',
        state: AgentActionState.active,
        config: CommandLineActionConfig(command: 'dir'),
        policies: AgentActionDefinitionPolicies(
          timeout: AgentActionTimeoutPolicy(
            maxRuntime: Duration.zero,
          ),
        ),
      );
      final neverCompletes = Completer<Result<AgentActionProcessResult>>();
      runner = FakeAgentActionLocalRunner(
        runHandler: () => neverCompletes.future,
      );
      repository.triggers['trigger-1'] = const AgentActionTrigger(
        id: 'trigger-1',
        actionId: 'action-1',
        type: AgentActionTriggerType.appClose,
      );
      final scheduler = createScheduler(
        now: () => DateTime(2026, 5, 15, 18),
      );

      final result = await scheduler.dispatchAppCloseTriggers(
        timeoutPerTrigger: Duration.zero,
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), 0);
      expect(runner.runCount, 1);
      expect(repository.triggers['trigger-1']?.lastRunAt, isNull);
    });
  });
}
