import 'package:plug_agente/domain/actions/action_enums.dart';

class AgentActionTriggerSchedule {
  const AgentActionTriggerSchedule({
    this.startAt,
    this.endAt,
    this.interval,
    this.timeOfDayMinutes,
    this.weekdays = const {},
    this.dayOfMonth,
    this.timezoneId,
    this.ignoreMissedRuns = true,
  });

  final DateTime? startAt;
  final DateTime? endAt;
  final Duration? interval;
  final int? timeOfDayMinutes;
  final Set<int> weekdays;
  final int? dayOfMonth;
  final String? timezoneId;
  final bool ignoreMissedRuns;

  bool get hasTimeOfDay {
    final value = timeOfDayMinutes;
    return value != null && value >= 0 && value < Duration.minutesPerDay;
  }

  AgentActionTriggerSchedule copyWith({
    DateTime? startAt,
    DateTime? endAt,
    Duration? interval,
    int? timeOfDayMinutes,
    Set<int>? weekdays,
    int? dayOfMonth,
    String? timezoneId,
    bool? ignoreMissedRuns,
  }) {
    return AgentActionTriggerSchedule(
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      interval: interval ?? this.interval,
      timeOfDayMinutes: timeOfDayMinutes ?? this.timeOfDayMinutes,
      weekdays: weekdays ?? this.weekdays,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      timezoneId: timezoneId ?? this.timezoneId,
      ignoreMissedRuns: ignoreMissedRuns ?? this.ignoreMissedRuns,
    );
  }
}

class AgentActionTrigger {
  const AgentActionTrigger({
    required this.id,
    required this.actionId,
    required this.type,
    this.name,
    this.isEnabled = true,
    this.schedule = const AgentActionTriggerSchedule(),
    this.lastScheduledAt,
    this.lastRunAt,
    this.nextRunAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String actionId;
  final AgentActionTriggerType type;
  final String? name;
  final bool isEnabled;
  final AgentActionTriggerSchedule schedule;
  final DateTime? lastScheduledAt;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isLifecycleTrigger {
    return type == AgentActionTriggerType.appStart || type == AgentActionTriggerType.appClose;
  }

  bool get isTemporalTrigger {
    return switch (type) {
      AgentActionTriggerType.once ||
      AgentActionTriggerType.interval ||
      AgentActionTriggerType.daily ||
      AgentActionTriggerType.weekly ||
      AgentActionTriggerType.monthly => true,
      AgentActionTriggerType.manual ||
      AgentActionTriggerType.remote ||
      AgentActionTriggerType.appStart ||
      AgentActionTriggerType.appClose => false,
    };
  }

  AgentActionTrigger copyWith({
    String? id,
    String? actionId,
    AgentActionTriggerType? type,
    String? name,
    bool? isEnabled,
    AgentActionTriggerSchedule? schedule,
    DateTime? lastScheduledAt,
    DateTime? lastRunAt,
    DateTime? nextRunAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearNextRunAt = false,
  }) {
    return AgentActionTrigger(
      id: id ?? this.id,
      actionId: actionId ?? this.actionId,
      type: type ?? this.type,
      name: name ?? this.name,
      isEnabled: isEnabled ?? this.isEnabled,
      schedule: schedule ?? this.schedule,
      lastScheduledAt: lastScheduledAt ?? this.lastScheduledAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      nextRunAt: clearNextRunAt ? null : nextRunAt ?? this.nextRunAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
