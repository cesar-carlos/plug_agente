import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/actions.dart';
import 'package:plug_agente/application/use_cases/dispatch_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/run_agent_action_locally.dart';
import 'package:plug_agente/application/use_cases/save_agent_action_trigger.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

import 'agent_action_trigger_scheduler_test.dart' as fixtures;

void main() {
  test('reports persisted failure when timer cannot be armed', () async {
    final repo = FailingScheduleRepository();
    final h = Harness(repository: repo);
    await h.scheduler.start();
    repo.failScheduling = true;
    final result =
        await SaveAgentActionTrigger(
          repo,
          const ValidateAgentActionTrigger(),
          FeatureFlags(InMemoryAppSettingsStore()),
          scheduler: h.scheduler,
        )(
          AgentActionTrigger(
            id: 't',
            actionId: 'a',
            type: AgentActionTriggerType.once,
            schedule: AgentActionTriggerSchedule(startAt: h.now.add(const Duration(hours: 1))),
          ),
        );
    expect(repo.failedWrites, 1);
    expect(result.isError(), isTrue);
    final failure = result.exceptionOrNull()! as ActionFailure;
    expect(failure.context['persisted'], isTrue);
    expect(failure.context['user_message'], contains('salvo'));
    expect(h.scheduler.scheduledTimerCount, 0);
    expect(repo.triggers['t']!.isEnabled, isTrue);
    repo.failScheduling = false;
    final retried = await SaveAgentActionTrigger(
      repo,
      const ValidateAgentActionTrigger(),
      FeatureFlags(InMemoryAppSettingsStore()),
      scheduler: h.scheduler,
    )(repo.triggers['t']!);
    expect(retried.isSuccess(), isTrue);
    expect(h.scheduler.scheduledTimerCount, 1);
    expect(repo.triggers.length, 1);
    h.scheduler.stop();
  });
  test('stopping during persistence does not arm a late timer', () async {
    final repo = PendingRuntimeRepository();
    final h = Harness(repository: repo);
    await h.scheduler.start();
    final trigger = AgentActionTrigger(
      id: 't',
      actionId: 'a',
      type: AgentActionTriggerType.once,
      schedule: AgentActionTriggerSchedule(startAt: h.now.add(const Duration(hours: 1))),
    );
    repo.triggers['t'] = trigger;
    final pending = h.scheduler.syncTrigger(trigger);
    await repo.entered.future;
    h.scheduler.stop();
    repo.release.complete();
    expect((await pending).getOrThrow(), isFalse);
    expect(h.scheduler.scheduledTimerCount, 0);
  });
  for (final lifecycle in [true, false]) {
    for (final remove in [true, false]) {
      test('${lifecycle ? 'lifecycle' : 'event'} completion preserves ${remove ? 'deletion' : 'disable'}', () async {
        final h = Harness();
        final trigger = AgentActionTrigger(
          id: 't',
          actionId: 'a',
          type: lifecycle ? AgentActionTriggerType.appStart : AgentActionTriggerType.actionSucceeded,
          schedule: AgentActionTriggerSchedule(sourceActionId: lifecycle ? null : 'source'),
        );
        h.repo.triggers['t'] = trigger;
        await h.scheduler.start();
        final pending = lifecycle
            ? h.scheduler.dispatchAppStartTriggers()
            : h.scheduler.dispatchExecutionTriggers(
                AgentActionExecution(
                  id: 'source-run',
                  actionId: 'source',
                  actionType: AgentActionType.executable,
                  status: AgentActionExecutionStatus.succeeded,
                  requestedAt: h.now,
                  source: AgentActionRequestSource.localUi,
                ),
              );
        await h.entered.future;
        if (remove) {
          await h.repo.deleteTrigger('t');
          h.scheduler.unscheduleTrigger('t');
        } else {
          final disabled = trigger.copyWith(isEnabled: false);
          await h.repo.saveTrigger(disabled);
          await h.scheduler.syncTrigger(disabled);
        }
        h.finish();
        expect((await pending).getOrThrow(), 1);
        if (remove) {
          expect(h.repo.triggers['t'], isNull);
        } else {
          expect(h.repo.triggers['t']!.isEnabled, isFalse);
        }
        h.scheduler.stop();
      });
    }
  }
  test('editing once while running preserves new schedule across restart', () async {
    final h = Harness();
    final trigger = AgentActionTrigger(
      id: 't',
      actionId: 'a',
      type: AgentActionTriggerType.once,
      schedule: AgentActionTriggerSchedule(startAt: h.now.add(const Duration(minutes: 1))),
    );
    h.repo.triggers['t'] = trigger;
    await h.scheduler.start();
    h.now = h.now.add(const Duration(minutes: 1));
    h.timers.single.fire();
    await h.entered.future;
    final changed = trigger.copyWith(
      schedule: AgentActionTriggerSchedule(startAt: h.now.add(const Duration(hours: 1))),
    );
    await h.repo.saveTrigger(changed);
    await h.scheduler.syncTrigger(changed);
    expect(h.repo.triggers['t']!.nextRunAt, changed.schedule.startAt);
    h.finish();
    await pumpEventQueue();
    expect(h.repo.triggers['t']!.lastScheduledAt, isNull);
    expect(h.repo.triggers['t']!.nextRunAt, changed.schedule.startAt);
    h.scheduler.stop();
    await h.scheduler.start();
    expect(h.scheduler.scheduledTimerCount, 1);
    h.scheduler.stop();
  });
}

class Harness {
  Harness({fixtures.FakeAgentActionRepository? repository})
    : repo = repository ?? fixtures.FakeAgentActionRepository() {
    repo.definitions['a'] = const AgentActionDefinition(
      id: 'a',
      name: 'test',
      state: AgentActionState.active,
      config: ExecutableActionConfig(executablePath: AgentActionPathReference(originalPath: r'C:\tools\test.exe')),
    );
    final runner = fixtures.FakeAgentActionLocalRunner(
      runHandler: () {
        entered.complete();
        return done.future;
      },
    );
    final run = RunAgentActionLocally(repo, AgentActionLocalRunnerRegistry([runner]), const Uuid(), now: () => now);
    scheduler = AgentActionTriggerScheduler(
      repo,
      DispatchAgentActionTrigger(repo, run, now: () => now),
      now: () => now,
      timerFactory: (delay, callback) {
        final timer = fixtures.FakeSchedulerTimer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
  }
  final fixtures.FakeAgentActionRepository repo;
  final entered = Completer<void>();
  final done = Completer<Result<AgentActionProcessResult>>();
  final timers = <fixtures.FakeSchedulerTimer>[];
  DateTime now = DateTime(2026, 5, 15, 8);
  late final AgentActionTriggerScheduler scheduler;

  void finish() => done.complete(
    Success(
      AgentActionProcessResult(
        status: AgentActionExecutionStatus.succeeded,
        pid: 1234,
        exitCode: 0,
        processStartedAt: now,
        finishedAt: now,
        stdout: AgentActionCapturedOutput.disabled,
        stderr: AgentActionCapturedOutput.disabled,
        redactionApplied: true,
      ),
    ),
  );
}

class FailingScheduleRepository extends fixtures.FakeAgentActionRepository {
  bool failScheduling = false;
  int failedWrites = 0;
  @override
  Future<Result<AgentActionTrigger>> saveTrigger(AgentActionTrigger trigger) async {
    if (failScheduling && trigger.nextRunAt != null) {
      failedWrites++;
      return Failure(ActionFailure.withContext(message: 'Simulated schedule persistence failure'));
    }
    return super.saveTrigger(trigger);
  }
}

class PendingRuntimeRepository extends fixtures.FakeAgentActionRepository {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<Result<bool>> updateTriggerRuntime(AgentActionTrigger expected, AgentActionTrigger updated) async {
    final result = await super.updateTriggerRuntime(expected, updated);
    entered.complete();
    await release.future;
    return result;
  }
}
