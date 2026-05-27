import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_trigger_schedule_calculator.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  setUpAll(ensureIanaTimeZoneDataLoaded);

  const calculator = AgentActionTriggerScheduleCalculator();

  group('AgentActionTriggerScheduleCalculator catch-up (ignoreMissedRuns=false)', () {
    test('should fire one-time trigger that was missed when ignoreMissedRuns=false', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-once',
          actionId: 'action-1',
          type: AgentActionTriggerType.once,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
            ignoreMissedRuns: false,
          ),
        ),
        now: DateTime(2026, 5, 15, 9),
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 15, 8));
    });

    test('should not fire one-time trigger that was missed when ignoreMissedRuns=true (default)', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-once',
          actionId: 'action-1',
          type: AgentActionTriggerType.once,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
          ),
        ),
        now: DateTime(2026, 5, 15, 9),
      );

      expect(result.getOrThrow().nextRunAt, isNull);
    });

    test('should fire interval missed slot once when ignoreMissedRuns=false and no lastScheduledAt', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-interval',
          actionId: 'action-1',
          type: AgentActionTriggerType.interval,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
            interval: const Duration(minutes: 15),
            ignoreMissedRuns: false,
          ),
        ),
        now: DateTime(2026, 5, 15, 8, 37),
      );

      // 8:00 -> 8:15 -> 8:30 (most recent missed slot before 8:37)
      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 15, 8, 30));
    });

    test('should not re-fire interval slot already at lastScheduledAt when ignoreMissedRuns=false', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-interval',
          actionId: 'action-1',
          type: AgentActionTriggerType.interval,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
            interval: const Duration(minutes: 15),
            ignoreMissedRuns: false,
          ),
          lastScheduledAt: DateTime(2026, 5, 15, 8, 30),
        ),
        now: DateTime(2026, 5, 15, 8, 37),
      );

      // Most recent missed slot (8:30) equals lastScheduledAt -> fallback to next future
      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 15, 8, 45));
    });

    test('should keep ignoring interval missed slots when ignoreMissedRuns=true (default)', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-interval',
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

    test('should fire daily missed slot today when ignoreMissedRuns=false', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-daily',
          actionId: 'action-1',
          type: AgentActionTriggerType.daily,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            ignoreMissedRuns: false,
          ),
        ),
        now: DateTime(2026, 5, 15, 10),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 15, 9));
    });

    test('should not fire daily missed slot already executed today', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-daily',
          actionId: 'action-1',
          type: AgentActionTriggerType.daily,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            ignoreMissedRuns: false,
          ),
          lastScheduledAt: DateTime(2026, 5, 15, 9),
        ),
        now: DateTime(2026, 5, 15, 10),
      );

      // Already ran today at 09:00; next is tomorrow.
      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 16, 9));
    });

    test('should fire weekly missed slot earlier this week when ignoreMissedRuns=false', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-weekly',
          actionId: 'action-1',
          type: AgentActionTriggerType.weekly,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            weekdays: const {DateTime.monday},
            ignoreMissedRuns: false,
          ),
        ),
        // Wed 2026-05-13 (Monday was 2026-05-11)
        now: DateTime(2026, 5, 13, 10),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 11, 9));
    });

    test('should fall back to next weekly slot when no missed slot since lastScheduledAt', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-weekly',
          actionId: 'action-1',
          type: AgentActionTriggerType.weekly,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            weekdays: const {DateTime.monday},
            ignoreMissedRuns: false,
          ),
          lastScheduledAt: DateTime(2026, 5, 11, 9),
        ),
        now: DateTime(2026, 5, 13, 10),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 18, 9));
    });

    test('should fire monthly missed slot this month when ignoreMissedRuns=false', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-monthly',
          actionId: 'action-1',
          type: AgentActionTriggerType.monthly,
          schedule: AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            dayOfMonth: 10,
            ignoreMissedRuns: false,
          ),
        ),
        now: DateTime(2026, 5, 15, 10),
      );

      expect(result.getOrThrow().nextRunAt, DateTime(2026, 5, 10, 9));
    });

    test('should still respect endAt when computing missed slot', () {
      final result = calculator.nextRun(
        trigger: AgentActionTrigger(
          id: 'trigger-once',
          actionId: 'action-1',
          type: AgentActionTriggerType.once,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime(2026, 5, 15, 8),
            endAt: DateTime(2026, 5, 15, 7),
            ignoreMissedRuns: false,
          ),
        ),
        now: DateTime(2026, 5, 15, 9),
      );

      expect(result.getOrThrow().nextRunAt, isNull);
    });
  });
}
