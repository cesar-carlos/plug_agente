import 'package:checks/checks.dart';
import 'package:plug_agente/application/mappers/agent_profile_hub_patch_mapper.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/application/validation/agent_profile_validation_messages.dart';
import 'package:test/test.dart';

void main() {
  group('agentProfileToHubPatchBody', () {
    test('should map profile to camelCase hub body with nested postalCode', () {
      final profileResult = AgentProfile.fromFormFields(
        name: 'ACME LTDA',
        tradeName: 'ACME',
        document: '59261947000107',
        phone: '1122223333',
        mobile: '65992865050',
        email: 'a@b.com',
        street: 'Av Brasil',
        number: '130',
        district: 'Centro',
        postalCode: '78300096',
        city: 'Tangará da Serra',
        state: 'mt',
        notes: 'Note',
        validationMessages: AgentProfileValidationMessages.english,
      );
      final profile = profileResult.getOrThrow();

      final body = agentProfileToHubPatchBody(profile);

      check(body['name']).equals('ACME LTDA');
      check(body['tradeName']).equals('ACME');
      check(body['document']).equals('59261947000107');
      check(body['documentType']).equals('cnpj');
      check(body['phone']).equals('1122223333');
      check(body['mobile']).equals('65992865050');
      check(body['email']).equals('a@b.com');
      check(body['notes']).equals('Note');

      final address = body['address'] as Map<String, dynamic>;
      check(address['street']).equals('Av Brasil');
      check(address['postalCode']).equals('78300096');
      check(address['state']).equals('MT');
    });

    test('should use JSON null for optional phone and notes when absent', () {
      final profileResult = AgentProfile.fromFormFields(
        name: 'ACME LTDA',
        tradeName: 'ACME',
        document: '59261947000107',
        phone: '',
        mobile: '65992865050',
        email: 'a@b.com',
        street: 'Av Brasil',
        number: '130',
        district: 'Centro',
        postalCode: '78300096',
        city: 'Tangará da Serra',
        state: 'mt',
        notes: '',
        validationMessages: AgentProfileValidationMessages.english,
      );
      final profile = profileResult.getOrThrow();

      final body = agentProfileToHubPatchBody(profile);

      check(body['phone']).isNull();
      check(body['notes']).isNull();
    });

    test('should include expectedProfileVersion and idempotencyKey when provided', () {
      final profileResult = AgentProfile.fromFormFields(
        name: 'ACME LTDA',
        tradeName: 'ACME',
        document: '59261947000107',
        phone: '',
        mobile: '65992865050',
        email: 'a@b.com',
        street: 'Av Brasil',
        number: '130',
        district: 'Centro',
        postalCode: '78300096',
        city: 'Tangará da Serra',
        state: 'mt',
        notes: '',
        validationMessages: AgentProfileValidationMessages.english,
      );
      final profile = profileResult.getOrThrow();

      final body = agentProfileToHubPatchBody(
        profile,
        expectedProfileVersion: 3,
        idempotencyKey: 'idem-1',
      );

      check(body['expectedProfileVersion']).equals(3);
      check(body['idempotencyKey']).equals('idem-1');
    });
  });
}
