import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/use_cases/validate_agent_action_trigger.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/domain/actions/actions.dart';

void main() {
  setUpAll(ensureIanaTimeZoneDataLoaded);

  group('ValidateAgentActionTrigger', () {
    const validator = ValidateAgentActionTrigger();

    AgentActionTrigger baseTrigger({
      required AgentActionTriggerType type,
      AgentActionTriggerSchedule schedule = const AgentActionTriggerSchedule(),
    }) {
      return AgentActionTrigger(
        id: 't-1',
        actionId: 'a-1',
        type: type,
        schedule: schedule,
      );
    }

    test('should accept valid IANA timezone for daily trigger', () async {
      final result = await validator.call(
        baseTrigger(
          type: AgentActionTriggerType.daily,
          schedule: const AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            timezoneId: 'America/New_York',
          ),
        ),
      );

      expect(result.isSuccess(), isTrue);
    });

    test('should reject unknown IANA timezone', () async {
      final result = await validator.call(
        baseTrigger(
          type: AgentActionTriggerType.daily,
          schedule: const AgentActionTriggerSchedule(
            timeOfDayMinutes: 9 * 60,
            timezoneId: 'Not/A_Real_Zone',
          ),
        ),
      );

      expect(result.isError(), isTrue);
    });

    test('should reject timezone on one-shot trigger', () async {
      final result = await validator.call(
        baseTrigger(
          type: AgentActionTriggerType.once,
          schedule: AgentActionTriggerSchedule(
            startAt: DateTime.utc(2026, 6, 1, 12),
            timezoneId: 'UTC',
          ),
        ),
      );

      expect(result.isError(), isTrue);
    });

    test('should reject timezone on interval trigger', () async {
      final result = await validator.call(
        baseTrigger(
          type: AgentActionTriggerType.interval,
          schedule: const AgentActionTriggerSchedule(
            interval: Duration(minutes: 30),
            timezoneId: 'UTC',
          ),
        ),
      );

      expect(result.isError(), isTrue);
    });

    test('should reject timezone on manual trigger', () async {
      final result = await validator.call(
        baseTrigger(
          type: AgentActionTriggerType.manual,
          schedule: const AgentActionTriggerSchedule(timezoneId: 'UTC'),
        ),
      );

      expect(result.isError(), isTrue);
    });
  });
}
