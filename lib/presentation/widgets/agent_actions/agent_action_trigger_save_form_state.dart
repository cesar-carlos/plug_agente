import 'package:flutter/material.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:uuid/uuid.dart';

final class AgentActionTriggerBuildResult {
  const AgentActionTriggerBuildResult({
    this.trigger,
    this.parseError,
  });

  final AgentActionTrigger? trigger;
  final String? parseError;
}

class AgentActionTriggerSaveFormState {
  AgentActionTriggerSaveFormState({AgentActionTrigger? existing})
    : nameController = TextEditingController(text: existing?.name ?? ''),
      _type = existing?.type ?? AgentActionTriggerType.manual,
      _isEnabled = existing?.isEnabled ?? true,
      _ignoreMissedRuns = existing?.schedule.ignoreMissedRuns ?? true,
      _weekdays = {...?existing?.schedule.weekdays},
      timezoneController = TextEditingController(
        text: _initialTimezone(existing),
      ),
      startAtController = TextEditingController(text: _formatDateTimeForField(existing?.schedule.startAt)),
      endAtController = TextEditingController(text: _formatDateTimeForField(existing?.schedule.endAt)),
      intervalMinutesController = TextEditingController(
        text: existing?.schedule.interval == null ? '' : '${existing!.schedule.interval!.inMinutes}',
      ),
      timeOfDayController = TextEditingController(text: _formatTimeOfDay(existing?.schedule.timeOfDayMinutes)),
      dayOfMonthController = TextEditingController(
        text: existing?.schedule.dayOfMonth == null ? '' : '${existing!.schedule.dayOfMonth}',
      );

  final TextEditingController nameController;
  final TextEditingController timezoneController;
  final TextEditingController startAtController;
  final TextEditingController endAtController;
  final TextEditingController intervalMinutesController;
  final TextEditingController timeOfDayController;
  final TextEditingController dayOfMonthController;

  AgentActionTriggerType _type;
  bool _isEnabled;
  bool _ignoreMissedRuns;
  final Set<int> _weekdays;
  String? parseError;

  AgentActionTriggerType get type => _type;
  bool get isEnabled => _isEnabled;
  bool get ignoreMissedRuns => _ignoreMissedRuns;
  Set<int> get weekdays => _weekdays;

  static String _initialTimezone(AgentActionTrigger? existing) {
    final initialType = existing?.type;
    final initialSupportsTimezone =
        initialType == AgentActionTriggerType.daily ||
        initialType == AgentActionTriggerType.weekly ||
        initialType == AgentActionTriggerType.monthly;
    return initialSupportsTimezone ? (existing?.schedule.timezoneId ?? '') : '';
  }

  void dispose() {
    nameController.dispose();
    timezoneController.dispose();
    startAtController.dispose();
    endAtController.dispose();
    intervalMinutesController.dispose();
    timeOfDayController.dispose();
    dayOfMonthController.dispose();
  }

  void setEnabled(bool value) {
    _isEnabled = value;
  }

  void setIgnoreMissedRuns(bool value) {
    _ignoreMissedRuns = value;
  }

  void toggleWeekday(int day, bool checked) {
    if (checked) {
      _weekdays.add(day);
    } else {
      _weekdays.remove(day);
    }
  }

  void applyTriggerTypeChange(AgentActionTriggerType value, {required AgentActionTriggerType previous}) {
    final wasTemporal =
        previous == AgentActionTriggerType.daily ||
        previous == AgentActionTriggerType.weekly ||
        previous == AgentActionTriggerType.monthly;
    final nowTemporal =
        value == AgentActionTriggerType.daily ||
        value == AgentActionTriggerType.weekly ||
        value == AgentActionTriggerType.monthly;
    if (wasTemporal && !nowTemporal) {
      timezoneController.clear();
    }
    _type = value;
    parseError = null;
  }

  bool get supportsMissedRunPolicy {
    return switch (_type) {
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

  AgentActionTriggerBuildResult buildTrigger({
    required AppLocalizations l10n,
    required String actionId,
    AgentActionTrigger? existing,
  }) {
    parseError = null;

    final id = existing?.id ?? const Uuid().v4();
    final nameRaw = nameController.text.trim();
    final name = nameRaw.isEmpty ? null : nameRaw;

    final AgentActionTriggerSchedule schedule;
    switch (_type) {
      case AgentActionTriggerType.manual:
      case AgentActionTriggerType.remote:
      case AgentActionTriggerType.appStart:
      case AgentActionTriggerType.appClose:
        schedule = const AgentActionTriggerSchedule();
      case AgentActionTriggerType.once:
        final startAt = _tryParseLocalDateTime(startAtController.text);
        if (startAt == null) {
          parseError = l10n.agentActionsTriggerValidationInvalidStartAt;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        final endAtOnce = _tryParseLocalDateTime(endAtController.text);
        schedule = AgentActionTriggerSchedule(
          startAt: startAt,
          endAt: endAtOnce,
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.interval:
        final minutes = int.tryParse(intervalMinutesController.text.trim());
        if (minutes == null || minutes <= 0) {
          parseError = l10n.agentActionsTriggerValidationInvalidIntervalMinutes;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        final startAtInterval = _tryParseLocalDateTime(startAtController.text);
        final endAtInterval = _tryParseLocalDateTime(endAtController.text);
        schedule = AgentActionTriggerSchedule(
          interval: Duration(minutes: minutes),
          startAt: startAtInterval,
          endAt: endAtInterval,
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.daily:
        final timeMinutes = _tryParseTimeOfDayMinutes(timeOfDayController.text);
        if (timeMinutes == null) {
          parseError = l10n.agentActionsTriggerValidationInvalidTimeOfDay;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        final startDaily = _tryParseLocalDateTime(startAtController.text);
        final endDaily = _tryParseLocalDateTime(endAtController.text);
        schedule = AgentActionTriggerSchedule(
          timeOfDayMinutes: timeMinutes,
          startAt: startDaily,
          endAt: endDaily,
          timezoneId: _timezoneOrNull(),
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.weekly:
        final timeWeekly = _tryParseTimeOfDayMinutes(timeOfDayController.text);
        if (timeWeekly == null) {
          parseError = l10n.agentActionsTriggerValidationInvalidTimeOfDay;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        if (_weekdays.isEmpty || _weekdays.any((int day) => day < 1 || day > 7)) {
          parseError = l10n.agentActionsTriggerValidationWeekdaysRequired;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        final startWeekly = _tryParseLocalDateTime(startAtController.text);
        final endWeekly = _tryParseLocalDateTime(endAtController.text);
        schedule = AgentActionTriggerSchedule(
          timeOfDayMinutes: timeWeekly,
          weekdays: _weekdays,
          startAt: startWeekly,
          endAt: endWeekly,
          timezoneId: _timezoneOrNull(),
          ignoreMissedRuns: _ignoreMissedRuns,
        );
      case AgentActionTriggerType.monthly:
        final timeMonthly = _tryParseTimeOfDayMinutes(timeOfDayController.text);
        if (timeMonthly == null) {
          parseError = l10n.agentActionsTriggerValidationInvalidTimeOfDay;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        final day = int.tryParse(dayOfMonthController.text.trim());
        if (day == null || day < 1 || day > 31) {
          parseError = l10n.agentActionsTriggerValidationInvalidDayOfMonth;
          return AgentActionTriggerBuildResult(parseError: parseError);
        }

        final startMonthly = _tryParseLocalDateTime(startAtController.text);
        final endMonthly = _tryParseLocalDateTime(endAtController.text);
        schedule = AgentActionTriggerSchedule(
          timeOfDayMinutes: timeMonthly,
          dayOfMonth: day,
          startAt: startMonthly,
          endAt: endMonthly,
          timezoneId: _timezoneOrNull(),
          ignoreMissedRuns: _ignoreMissedRuns,
        );
    }

    return AgentActionTriggerBuildResult(
      trigger: AgentActionTrigger(
        id: id,
        actionId: actionId,
        type: _type,
        name: name,
        isEnabled: _isEnabled,
        schedule: schedule,
        lastScheduledAt: existing?.lastScheduledAt,
        lastRunAt: existing?.lastRunAt,
        nextRunAt: existing?.nextRunAt,
        createdAt: existing?.createdAt,
      ),
    );
  }

  static String _formatDateTimeForField(DateTime? value) {
    if (value == null) {
      return '';
    }

    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  static String _formatTimeOfDay(int? minutes) {
    if (minutes == null || minutes < 0 || minutes >= Duration.minutesPerDay) {
      return '';
    }

    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static DateTime? _tryParseLocalDateTime(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final normalized = trimmed.contains('T') ? trimmed : trimmed.replaceFirst(RegExp(r'\s+'), 'T');
    return DateTime.tryParse(normalized);
  }

  static int? _tryParseTimeOfDayMinutes(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final parts = trimmed.split(':');
    if (parts.length != 2) {
      return null;
    }

    final h = int.tryParse(parts[0].trim());
    final m = int.tryParse(parts[1].trim());
    if (h == null || m == null) {
      return null;
    }

    if (h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }

    return h * Duration.minutesPerHour + m;
  }

  String? _timezoneOrNull() {
    final trimmed = timezoneController.text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
