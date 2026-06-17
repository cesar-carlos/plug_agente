import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_profile_lookup_gateways.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cep.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:result_dart/result_dart.dart';

class _MockViaCepLookup extends Mock implements IViaCepLookup {}

const _testErrorMessages = ViaCepLookupErrorMessages(
  emptyResponse: 'empty response',
  notFound: 'not found',
  invalidPayload: 'invalid payload',
  networkError: 'network error',
  unexpectedError: 'unexpected error',
);

void main() {
  group('LookupAgentCep', () {
    late _MockViaCepLookup gateway;
    late LookupAgentCep useCase;

    setUpAll(() {
      registerFallbackValue(_testErrorMessages);
    });

    setUp(() {
      gateway = _MockViaCepLookup();
      useCase = LookupAgentCep(gateway);
    });

    test('returns ValidationFailure when sanitized input is shorter than 8 digits', () async {
      final result = await useCase(
        rawPostalCode: '0100',
        invalidLengthMessage: 'invalid cep',
        errorMessages: _testErrorMessages,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).message, equals('invalid cep'));
      verifyNever(
        () => gateway.lookupCep(any(), errorMessages: any(named: 'errorMessages')),
      );
    });

    test('delegates sanitized digits to gateway when input has 8 digits', () async {
      when(
        () => gateway.lookupCep(
          '01001000',
          errorMessages: _testErrorMessages,
        ),
      ).thenAnswer(
        (_) async => const Success(
          ViaCepAddress(
            cep: '01001-000',
            logradouro: 'Praça da Sé',
            bairro: 'Sé',
            localidade: 'São Paulo',
            uf: 'SP',
          ),
        ),
      );

      final result = await useCase(
        rawPostalCode: '01001-000',
        invalidLengthMessage: 'invalid cep',
        errorMessages: _testErrorMessages,
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => gateway.lookupCep(
          '01001000',
          errorMessages: _testErrorMessages,
        ),
      ).called(1);
    });
  });
}
