import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';
import 'package:timezone/timezone.dart' as tz;

class AgentActionScheduleDecision {
  const AgentActionScheduleDecision({
    required this.triggerId,
    required this.calculatedAt,
    this.nextRunAt,
  });

  final String triggerId;
  final DateTime calculatedAt;
  final DateTime? nextRunAt;

  bool get hasNextRun => nextRunAt != null;
}

class AgentActionTriggerScheduleCalculator {
  const AgentActionTriggerScheduleCalculator();

  Result<AgentActionScheduleDecision> nextRun({
    required AgentActionTrigger trigger,
    required DateTime now,
  }) {
    if (!trigger.isTemporalTrigger) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action trigger type does not support temporal scheduling.',
          context: {
            'trigger_id': trigger.id,
            'trigger_type': trigger.type.name,
            'reason': AgentActionTriggerConstants.nonTemporalTriggerReason,
            'user_message': 'Este tipo de gatilho nao usa agendamento temporal.',
          },
        ),
      );
    }

    final nextRunAt = switch (trigger.type) {
      AgentActionTriggerType.once => _nextOnce(trigger, now),
      AgentActionTriggerType.interval => _nextInterval(trigger, now),
      AgentActionTriggerType.daily => _nextDaily(trigger, now),
      AgentActionTriggerType.weekly => _nextWeekly(trigger, now),
      AgentActionTriggerType.monthly => _nextMonthly(trigger, now),
      AgentActionTriggerType.manual ||
      AgentActionTriggerType.remote ||
      AgentActionTriggerType.appStart ||
      AgentActionTriggerType.appClose => null,
    };

    return Success(
      AgentActionScheduleDecision(
        triggerId: trigger.id,
        calculatedAt: now,
        nextRunAt: nextRunAt,
      ),
    );
  }

  tz.Location? _tryResolveLocation(AgentActionTrigger trigger) {
    final id = trigger.schedule.timezoneId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    try {
      ensureIanaTimeZoneDataLoaded();
      return tz.getLocation(id);
    } on Object {
      return null;
    }
  }

  DateTime? _nextOnce(
    AgentActionTrigger trigger,
    DateTime now,
  ) {
    if (trigger.lastScheduledAt != null) {
      return null;
    }

    final startAt = trigger.schedule.startAt;
    if (startAt == null || startAt.isBefore(now)) {
      return null;
    }

    return _withinEnd(trigger, startAt) ? startAt : null;
  }

  DateTime? _nextInterval(
    AgentActionTrigger trigger,
    DateTime now,
  ) {
    final interval = trigger.schedule.interval;
    if (interval == null || interval <= Duration.zero) {
      return null;
    }

    final anchor = trigger.schedule.startAt ?? now;
    if (!anchor.isBefore(now)) {
      return _withinEnd(trigger, anchor) ? anchor : null;
    }

    final elapsedMicros = now.difference(anchor).inMicroseconds;
    final intervalMicros = interval.inMicroseconds;
    var steps = elapsedMicros ~/ intervalMicros;
    if (elapsedMicros % intervalMicros != 0) {
      steps += 1;
    }

    final next = anchor.add(Duration(microseconds: intervalMicros * steps));
    return _withinEnd(trigger, next) ? next : null;
  }

  DateTime? _nextDaily(
    AgentActionTrigger trigger,
    DateTime now,
  ) {
    final timeOfDay = trigger.schedule.timeOfDayMinutes;
    if (timeOfDay == null) {
      return null;
    }

    final location = _tryResolveLocation(trigger);
    if (location != null) {
      return _nextDailyInLocation(trigger, now, location, timeOfDay);
    }

    final base = _effectiveBase(trigger, now);
    var candidate = _atTimeOfDay(base, timeOfDay);
    if (candidate.isBefore(base)) {
      candidate = candidate.add(const Duration(days: 1));
    }

    return _withinEnd(trigger, candidate) ? candidate : null;
  }

  DateTime? _nextDailyInLocation(
    AgentActionTrigger trigger,
    DateTime now,
    tz.Location location,
    int timeOfDayMinutes,
  ) {
    final baseInstant = _effectiveBase(trigger, now);
    final baseTz = tz.TZDateTime.from(baseInstant, location);
    var candidate = _tzAtTimeOfDay(location, baseTz, timeOfDayMinutes);
    if (candidate.isBefore(baseTz)) {
      candidate = _tzAtTimeOfDay(location, baseTz.add(const Duration(days: 1)), timeOfDayMinutes);
    }

    return _withinEnd(trigger, candidate) ? candidate : null;
  }

  DateTime? _nextWeekly(
    AgentActionTrigger trigger,
    DateTime now,
  ) {
    final timeOfDay = trigger.schedule.timeOfDayMinutes;
    if (timeOfDay == null || trigger.schedule.weekdays.isEmpty) {
      return null;
    }

    final location = _tryResolveLocation(trigger);
    if (location != null) {
      return _nextWeeklyInLocation(trigger, now, location, timeOfDay);
    }

    final base = _effectiveBase(trigger, now);
    for (var offset = 0; offset <= DateTime.daysPerWeek; offset += 1) {
      final date = DateTime(base.year, base.month, base.day).add(Duration(days: offset));
      if (!trigger.schedule.weekdays.contains(date.weekday)) {
        continue;
      }

      final candidate = _atTimeOfDay(date, timeOfDay);
      if (candidate.isBefore(base)) {
        continue;
      }

      return _withinEnd(trigger, candidate) ? candidate : null;
    }

    return null;
  }

  DateTime? _nextWeeklyInLocation(
    AgentActionTrigger trigger,
    DateTime now,
    tz.Location location,
    int timeOfDayMinutes,
  ) {
    final baseInstant = _effectiveBase(trigger, now);
    final baseTz = tz.TZDateTime.from(baseInstant, location);
    final startCal = tz.TZDateTime(location, baseTz.year, baseTz.month, baseTz.day);

    for (var offset = 0; offset <= DateTime.daysPerWeek; offset += 1) {
      final dateTz = startCal.add(Duration(days: offset));
      if (!trigger.schedule.weekdays.contains(dateTz.weekday)) {
        continue;
      }

      final candidate = _tzAtTimeOfDay(location, dateTz, timeOfDayMinutes);
      if (candidate.isBefore(baseTz)) {
        continue;
      }

      return _withinEnd(trigger, candidate) ? candidate : null;
    }

    return null;
  }

  DateTime? _nextMonthly(
    AgentActionTrigger trigger,
    DateTime now,
  ) {
    final timeOfDay = trigger.schedule.timeOfDayMinutes;
    final dayOfMonth = trigger.schedule.dayOfMonth;
    if (timeOfDay == null || dayOfMonth == null) {
      return null;
    }

    final location = _tryResolveLocation(trigger);
    if (location != null) {
      return _nextMonthlyInLocation(trigger, now, location, timeOfDay, dayOfMonth);
    }

    final base = _effectiveBase(trigger, now);
    for (var offset = 0; offset < 36; offset += 1) {
      final monthStart = DateTime(base.year, base.month + offset);
      if (dayOfMonth > _daysInMonth(monthStart.year, monthStart.month)) {
        continue;
      }

      final candidate = _atTimeOfDay(
        DateTime(monthStart.year, monthStart.month, dayOfMonth),
        timeOfDay,
      );
      if (candidate.isBefore(base)) {
        continue;
      }

      return _withinEnd(trigger, candidate) ? candidate : null;
    }

    return null;
  }

  DateTime? _nextMonthlyInLocation(
    AgentActionTrigger trigger,
    DateTime now,
    tz.Location location,
    int timeOfDayMinutes,
    int dayOfMonth,
  ) {
    final baseInstant = _effectiveBase(trigger, now);
    final baseTz = tz.TZDateTime.from(baseInstant, location);

    for (var offset = 0; offset < 36; offset += 1) {
      final cal = DateTime(baseTz.year, baseTz.month + offset);
      if (dayOfMonth > _daysInMonth(cal.year, cal.month)) {
        continue;
      }

      final candidate = tz.TZDateTime(
        location,
        cal.year,
        cal.month,
        dayOfMonth,
        timeOfDayMinutes ~/ Duration.minutesPerHour,
        timeOfDayMinutes % Duration.minutesPerHour,
      );
      if (candidate.isBefore(baseTz)) {
        continue;
      }

      return _withinEnd(trigger, candidate) ? candidate : null;
    }

    return null;
  }

  DateTime _effectiveBase(
    AgentActionTrigger trigger,
    DateTime now,
  ) {
    final startAt = trigger.schedule.startAt;
    if (startAt == null || startAt.isBefore(now)) {
      return now;
    }

    return startAt;
  }

  tz.TZDateTime _tzAtTimeOfDay(
    tz.Location location,
    tz.TZDateTime dayInLocation,
    int timeOfDayMinutes,
  ) {
    return tz.TZDateTime(
      location,
      dayInLocation.year,
      dayInLocation.month,
      dayInLocation.day,
      timeOfDayMinutes ~/ Duration.minutesPerHour,
      timeOfDayMinutes % Duration.minutesPerHour,
    );
  }

  DateTime _atTimeOfDay(DateTime date, int minutes) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      minutes ~/ Duration.minutesPerHour,
      minutes % Duration.minutesPerHour,
    );
  }

  bool _withinEnd(
    AgentActionTrigger trigger,
    DateTime candidate,
  ) {
    final endAt = trigger.schedule.endAt;
    return endAt == null || !candidate.isAfter(endAt);
  }

  int _daysInMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }
}
