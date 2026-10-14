import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_trigger_schedule_calculator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations_pt.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_trigger_save_form_state.dart';

void main() {
  final l10n = AppLocalizationsPt();
  test('retrying a new trigger preserves its identity', () {
    final form = AgentActionTriggerSaveFormState();
    addTearDown(form.dispose);
    final first = form.buildTrigger(l10n: l10n, actionId: 'a').trigger!;
    form.nameController.text = 'Retry';
    final retry = form.buildTrigger(l10n: l10n, actionId: 'a').trigger!;
    expect(retry.id, first.id);
  });
  for (final raw in [
    '2026-02-31 10:00',
    '2026-13-01 10:00',
    '2026-10-14 24:30',
    '2026-10-14 12:60',
    '2026-02-29 10:00',
  ]) {
    test('rejects invalid date $raw beside the start field', () {
      final form = AgentActionTriggerSaveFormState();
      addTearDown(form.dispose);
      form.applyTriggerTypeChange(AgentActionTriggerType.once, previous: form.type);
      form.startAtController.text = raw;
      expect(form.buildTrigger(l10n: l10n, actionId: 'a').trigger, isNull);
      expect(form.fieldErrors, contains(form.startAtController));
    });
  }
  test('accepts leap day and preserves seconds when renaming', () {
    final start = DateTime(2028, 2, 29, 10, 20, 35, 123, 456);
    final existing = AgentActionTrigger(
      id: 't',
      actionId: 'a',
      type: AgentActionTriggerType.once,
      schedule: AgentActionTriggerSchedule(startAt: start),
    );
    final form = AgentActionTriggerSaveFormState(existing: existing);
    addTearDown(form.dispose);
    form.nameController.text = 'Renamed';
    expect(form.buildTrigger(l10n: l10n, actionId: 'a', existing: existing).trigger!.schedule.startAt, start);
  });
  for (final duration in [
    const Duration(seconds: 90),
    const Duration(seconds: 30),
    const Duration(microseconds: 1234567),
  ]) {
    test('renaming preserves interval $duration', () {
      final existing = AgentActionTrigger(
        id: 't',
        actionId: 'a',
        type: AgentActionTriggerType.interval,
        schedule: AgentActionTriggerSchedule(interval: duration),
      );
      final form = AgentActionTriggerSaveFormState(existing: existing);
      addTearDown(form.dispose);
      form.nameController.text = 'New name';
      expect(form.buildTrigger(l10n: l10n, actionId: 'a', existing: existing).trigger!.schedule.interval, duration);
    });
  }
  test('decimal comma allows an explicit interval change', () {
    final form = AgentActionTriggerSaveFormState();
    addTearDown(form.dispose);
    form.applyTriggerTypeChange(AgentActionTriggerType.interval, previous: form.type);
    form.intervalMinutesController.text = '1,5';
    expect(form.buildTrigger(l10n: l10n, actionId: 'a').trigger!.schedule.interval, const Duration(seconds: 90));
  });
  test('rearming requires consent, preserves history, and schedules the new date', () {
    final oldDate = DateTime(2026, 10, 1, 10);
    final existing = AgentActionTrigger(
      id: 't',
      actionId: 'a',
      type: AgentActionTriggerType.once,
      schedule: AgentActionTriggerSchedule(startAt: oldDate),
      lastScheduledAt: oldDate,
      lastRunAt: oldDate,
    );
    final form = AgentActionTriggerSaveFormState(existing: existing);
    addTearDown(form.dispose);
    form.startAtController.text = '2026-11-01 10:00';
    expect(form.buildTrigger(l10n: l10n, actionId: 'a', existing: existing).trigger, isNull);
    expect(form.selectionErrorKey, 'rearm');
    form.rearmOnce = true;
    final trigger = form.buildTrigger(l10n: l10n, actionId: 'a', existing: existing).trigger!;
    expect(trigger.lastRunAt, oldDate);
    expect(trigger.lastScheduledAt, isNull);
    expect(
      const AgentActionTriggerScheduleCalculator()
          .nextRun(trigger: trigger, now: DateTime(2026, 10, 14))
          .getOrThrow()
          .nextRunAt,
      DateTime(2026, 11, 1, 10),
    );
    form.startAtController.text = '2026-10-01 10:00';
    expect(form.buildTrigger(l10n: l10n, actionId: 'a', existing: existing).trigger!.lastScheduledAt, oldDate);
  });
  test('invalid timezone and end range identify the relevant field', () {
    final form = AgentActionTriggerSaveFormState();
    addTearDown(form.dispose);
    form.applyTriggerTypeChange(AgentActionTriggerType.daily, previous: form.type);
    form.timeOfDayController.text = '10:00';
    form.timezoneController.text = 'unknown/timezone';
    expect(form.buildTrigger(l10n: l10n, actionId: 'a').trigger, isNull);
    expect(form.fieldErrors, contains(form.timezoneController));
    form.timezoneController.text = 'America/Cuiaba';
    form.startAtController.text = '2026-10-14 10:00';
    form.endAtController.text = '2026-10-13 10:00';
    expect(form.buildTrigger(l10n: l10n, actionId: 'a').trigger, isNull);
    expect(form.fieldErrors, contains(form.endAtController));
  });
}
