import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_com_object_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/com_object_argument_validator.dart';

void main() {
  group('ComObjectArgumentValidator', () {
    test('should accept supported scalar types and return immutable map', () {
      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: <String, Object?>{
          'flag': true,
          'count': 3,
          'ratio': 1.5,
          'label': 'ok',
        },
      );

      expect(result.isSuccess(), isTrue);
      final normalized = result.getOrThrow();
      expect(normalized, hasLength(4));
      expect(() => normalized['extra'] = 'denied', throwsUnsupportedError);
    });

    test('should trim argument keys before storing', () {
      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: const <String, Object?>{'  key ': 'value'},
      );

      expect(result.getOrThrow().keys, contains('key'));
    });

    test('should reject map larger than max entries with stable reason', () {
      final overflow = <String, Object?>{
        for (var i = 0; i <= AgentActionComObjectConstants.maxArgumentEntries; i += 1) 'k$i': i,
      };

      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: overflow,
        phase: 'execution_preflight',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionComObjectConstants.invalidArgumentsReason);
      expect(failure.context['phase'], 'execution_preflight');
      expect(failure.context['max_entries'], AgentActionComObjectConstants.maxArgumentEntries);
    });

    test('should reject empty or whitespace-only key', () {
      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: const <String, Object?>{'   ': 'value'},
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionComObjectConstants.invalidArgumentsReason);
    });

    test('should reject key longer than the configured limit', () {
      final longKey = List<String>.filled(
        AgentActionComObjectConstants.maxArgumentKeyLength + 1,
        'k',
      ).join();

      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: <String, Object?>{longKey: 'value'},
      );

      expect(result.isError(), isTrue);
    });

    test('should reject string argument longer than the configured limit with key in context', () {
      final overflowValue = List<String>.filled(
        AgentActionComObjectConstants.maxStringArgumentLength + 1,
        'a',
      ).join();

      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: <String, Object?>{'payload': overflowValue},
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['argument_key'], 'payload');
      expect(failure.context['reason'], AgentActionComObjectConstants.invalidArgumentsReason);
    });

    test('should reject null argument value with stable reason', () {
      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: const <String, Object?>{'maybe': null},
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['argument_key'], 'maybe');
    });

    test('should reject unsupported value types like List or Map', () {
      final result = ComObjectArgumentValidator.validate(
        actionId: 'action-1',
        arguments: const <String, Object?>{
          'items': <int>[1, 2],
        },
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['argument_key'], 'items');
      expect(failure.context['value_type'], isNotNull);
    });
  });
}
