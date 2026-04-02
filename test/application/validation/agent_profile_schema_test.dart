import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/validation/agent_profile_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

void main() {
  group('AgentProfile', () {
    test('should normalize valid form fields', () {
      final result = AgentProfile.fromFormFields(
        name: 'Empresa Exemplo',
        tradeName: 'Fantasia Exemplo',
        document: '529.982.247-25',
        phone: '(11) 3333-4444',
        mobile: '(11) 98888-7777',
        email: 'CONTATO@EXEMPLO.COM ',
        street: 'Rua Central',
        number: '123',
        district: 'Centro',
        postalCode: '01001-000',
        city: 'Sao Paulo',
        state: 'sp',
        notes: 'Observacao de teste',
      );

      check(result.isSuccess()).isTrue();
      final profile = result.getOrThrow();
      check(profile.document).equals('52998224725');
      check(profile.documentType).equals('cpf');
      check(profile.phone).equals('1133334444');
      check(profile.mobile).equals('11988887777');
      check(profile.email).equals('contato@exemplo.com');
      check(profile.address.postalCode).equals('01001000');
      check(profile.address.state).equals('SP');
    });

    test('should fail when city and state are missing', () {
      final result = AgentProfile.fromFormFields(
        name: 'Empresa Exemplo',
        tradeName: 'Fantasia Exemplo',
        document: '529.982.247-25',
        phone: '',
        mobile: '(11) 98888-7777',
        email: 'contato@exemplo.com',
        street: 'Rua Central',
        number: '123',
        district: 'Centro',
        postalCode: '01001-000',
        city: '',
        state: '',
        notes: '',
      );

      check(result.isError()).isTrue();
      final failure = result.exceptionOrNull()! as domain.ValidationFailure;
      check(failure.message).contains('Municipio');
      check(failure.message).contains('UF');
    });
  });
}
