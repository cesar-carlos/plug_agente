import 'package:plug_agente/core/constants/agent_action_trigger_constants.dart';
import 'package:plug_agente/core/constants/agent_action_validation_constants.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:result_dart/result_dart.dart';
import 'package:timezone/timezone.dart' as tz;

class ValidateAgentActionTrigger {
  const ValidateAgentActionTrigger();

  Future<Result<AgentActionTrigger>> call(
    AgentActionTrigger trigger,
  ) async {
    final failure = _validate(trigger);
    if (failure != null) {
      return Failure(failure);
    }

    return Success(trigger);
  }

  ActionValidationFailure? _validate(AgentActionTrigger trigger) {
    if (trigger.id.trim().isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Action trigger id is required.',
        context: const {
          'field': 'id',
          'reason': AgentActionValidationConstants.fieldRequiredReason,
          'user_message': 'Informe o identificador do gatilho.',
        },
      );
    }
    if (trigger.actionId.trim().isEmpty) {
      return ActionValidationFailure.withContext(
        message: 'Action id is required for the trigger.',
        context: const {
          'field': 'actionId',
          'reason': AgentActionValidationConstants.fieldRequiredReason,
          'user_message': 'Informe a acao vinculada ao gatilho.',
        },
      );
    }

    final timezoneFailure = _validateTimezoneId(trigger);
    if (timezoneFailure != null) {
      return timezoneFailure;
    }

    return switch (trigger.type) {
      AgentActionTriggerType.once => _validateOnce(trigger),
      AgentActionTriggerType.interval => _validateInterval(trigger),
      AgentActionTriggerType.daily => _validateDaily(trigger),
      AgentActionTriggerType.weekly => _validateWeekly(trigger),
      AgentActionTriggerType.monthly => _validateMonthly(trigger),
      AgentActionTriggerType.manual ||
      AgentActionTriggerType.remote ||
      AgentActionTriggerType.appStart ||
      AgentActionTriggerType.appClose => _validateNonTemporal(trigger),
    };
  }

  ActionValidationFailure? _validateTimezoneId(AgentActionTrigger trigger) {
    final id = trigger.schedule.timezoneId?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }

    if (trigger.type == AgentActionTriggerType.once || trigger.type == AgentActionTriggerType.interval) {
      return _failure(
        field: 'schedule.timezoneId',
        reason: AgentActionTriggerConstants.timezoneNotSupportedForTriggerTypeReason,
        userMessage:
            'Fuso IANA so e aplicado a gatilhos diarios, semanais e mensais. Remova o campo ou altere o tipo do gatilho.',
      );
    }

    try {
      ensureIanaTimeZoneDataLoaded();
      tz.getLocation(id);
    } on tz.LocationNotFoundException {
      return _failure(
        field: 'schedule.timezoneId',
        reason: AgentActionTriggerConstants.unknownTimezoneReason,
        userMessage: 'Informe um fuso IANA valido (ex.: America/Sao_Paulo, Europe/Lisbon, UTC).',
      );
    }

    return null;
  }

  ActionValidationFailure? _validateOnce(AgentActionTrigger trigger) {
    if (trigger.schedule.startAt == null) {
      return _failure(
        field: 'schedule.startAt',
        reason: AgentActionTriggerConstants.requiredForOnceReason,
        userMessage: 'Informe a data e hora da execucao unica.',
      );
    }

    return _validateDateRange(trigger);
  }

  ActionValidationFailure? _validateInterval(AgentActionTrigger trigger) {
    final interval = trigger.schedule.interval;
    if (interval == null || interval <= Duration.zero) {
      return _failure(
        field: 'schedule.interval',
        reason: AgentActionTriggerConstants.requiredForIntervalReason,
        userMessage: 'Informe um intervalo maior que zero.',
      );
    }

    return _validateDateRange(trigger);
  }

  ActionValidationFailure? _validateDaily(AgentActionTrigger trigger) {
    if (!trigger.schedule.hasTimeOfDay) {
      return _invalidTimeOfDay();
    }

    return _validateDateRange(trigger);
  }

  ActionValidationFailure? _validateWeekly(AgentActionTrigger trigger) {
    if (!trigger.schedule.hasTimeOfDay) {
      return _invalidTimeOfDay();
    }
    if (trigger.schedule.weekdays.isEmpty || trigger.schedule.weekdays.any((day) => day < 1 || day > 7)) {
      return _failure(
        field: 'schedule.weekdays',
        reason: AgentActionTriggerConstants.invalidWeekdaysReason,
        userMessage: 'Selecione pelo menos um dia da semana valido.',
      );
    }

    return _validateDateRange(trigger);
  }

  ActionValidationFailure? _validateMonthly(AgentActionTrigger trigger) {
    if (!trigger.schedule.hasTimeOfDay) {
      return _invalidTimeOfDay();
    }
    final day = trigger.schedule.dayOfMonth;
    if (day == null || day < 1 || day > 31) {
      return _failure(
        field: 'schedule.dayOfMonth',
        reason: AgentActionTriggerConstants.invalidDayOfMonthReason,
        userMessage: 'Informe um dia do mes entre 1 e 31.',
      );
    }

    return _validateDateRange(trigger);
  }

  ActionValidationFailure? _validateNonTemporal(AgentActionTrigger trigger) {
    if (trigger.schedule.timezoneId?.trim().isNotEmpty ?? false) {
      return _failure(
        field: 'schedule.timezoneId',
        reason: AgentActionTriggerConstants.timezoneNotSupportedForTriggerTypeReason,
        userMessage:
            'Fuso IANA so e usado em gatilhos com agendamento temporal (diario, semanal, mensal, etc.). Remova o campo.',
      );
    }
    if (trigger.schedule.startAt != null ||
        trigger.schedule.interval != null ||
        trigger.schedule.timeOfDayMinutes != null) {
      return _failure(
        field: 'schedule',
        reason: AgentActionTriggerConstants.scheduleNotSupportedReason,
        userMessage: 'Este tipo de gatilho nao usa configuracao temporal.',
      );
    }

    return null;
  }

  ActionValidationFailure? _validateDateRange(AgentActionTrigger trigger) {
    final startAt = trigger.schedule.startAt;
    final endAt = trigger.schedule.endAt;
    if (startAt != null && endAt != null && !endAt.isAfter(startAt)) {
      return _failure(
        field: 'schedule.endAt',
        reason: AgentActionTriggerConstants.endBeforeStartReason,
        userMessage: 'A data final precisa ser maior que a data inicial.',
      );
    }

    return null;
  }

  ActionValidationFailure _invalidTimeOfDay() {
    return _failure(
      field: 'schedule.timeOfDayMinutes',
      reason: AgentActionTriggerConstants.invalidTimeOfDayReason,
      userMessage: 'Informe um horario valido para o gatilho.',
    );
  }

  ActionValidationFailure _failure({
    required String field,
    required String reason,
    required String userMessage,
  }) {
    return ActionValidationFailure.withContext(
      message: 'Action trigger schedule is invalid.',
      context: {
        'field': field,
        'reason': reason,
        'user_message': userMessage,
      },
    );
  }
}
