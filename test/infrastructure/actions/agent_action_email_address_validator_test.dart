import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/agent_action_email_constants.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/infrastructure/actions/agent_action_email_address_validator.dart';

void main() {
  group('AgentActionEmailAddressValidator.validateAddress', () {
    test('should accept canonical address and trim surrounding whitespace', () {
      final result = AgentActionEmailAddressValidator.validateAddress(
        actionId: 'a-1',
        field: 'from',
        address: '  ops@local.example.com  ',
      );

      expect(result.getOrThrow(), 'ops@local.example.com');
    });

    test('should accept address with template token without applying regex', () {
      final result = AgentActionEmailAddressValidator.validateAddress(
        actionId: 'a-1',
        field: 'to',
        address: '{{recipient}}',
      );

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), '{{recipient}}');
    });

    test('should reject empty address with stable reason', () {
      final result = AgentActionEmailAddressValidator.validateAddress(
        actionId: 'a-1',
        field: 'from',
        address: '   ',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.invalidEmailAddressReason);
      expect(failure.context['field'], 'from');
    });

    test('should reject malformed address with stable reason', () {
      final result = AgentActionEmailAddressValidator.validateAddress(
        actionId: 'a-1',
        field: 'to',
        address: 'not-an-email',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.invalidEmailAddressReason);
    });
  });

  group('AgentActionEmailAddressValidator.validateRecipientList', () {
    test('should return empty list when not required and addresses is empty', () {
      final result = AgentActionEmailAddressValidator.validateRecipientList(
        actionId: 'a-1',
        field: 'cc',
        addresses: const <String>[],
        required: false,
      );

      expect(result.getOrThrow(), isEmpty);
    });

    test('should fail when required and addresses is empty', () {
      final result = AgentActionEmailAddressValidator.validateRecipientList(
        actionId: 'a-1',
        field: 'to',
        addresses: const <String>[],
        required: true,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.invalidEmailAddressReason);
    });

    test('should reject list exceeding max recipients with stable reason', () {
      final addresses = List<String>.generate(
        AgentActionEmailConstants.maxRecipientsPerList + 1,
        (index) => 'user$index@example.com',
      );

      final result = AgentActionEmailAddressValidator.validateRecipientList(
        actionId: 'a-1',
        field: 'to',
        addresses: addresses,
        required: true,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as ActionValidationFailure;
      expect(failure.context['reason'], AgentActionEmailConstants.tooManyRecipientsReason);
      expect(failure.context['max_recipients'], AgentActionEmailConstants.maxRecipientsPerList);
    });

    test('should normalize all addresses and return immutable list', () {
      final result = AgentActionEmailAddressValidator.validateRecipientList(
        actionId: 'a-1',
        field: 'to',
        addresses: const <String>[' ops@example.com ', 'audit@example.com'],
        required: true,
      );

      final normalized = result.getOrThrow();
      expect(normalized, ['ops@example.com', 'audit@example.com']);
      expect(() => normalized.add('extra@example.com'), throwsUnsupportedError);
    });

    test('should fail when any address is invalid and stop at that entry', () {
      final result = AgentActionEmailAddressValidator.validateRecipientList(
        actionId: 'a-1',
        field: 'to',
        addresses: const <String>['ok@example.com', 'broken'],
        required: true,
      );

      expect(result.isError(), isTrue);
    });
  });

  group('AgentActionEmailAddressValidator.containsTemplateTokens', () {
    test('should detect placeholder tokens', () {
      expect(AgentActionEmailAddressValidator.containsTemplateTokens('{{name}}@x'), isTrue);
    });

    test('should ignore literal strings without placeholders', () {
      expect(AgentActionEmailAddressValidator.containsTemplateTokens('user@example.com'), isFalse);
    });
  });
}
