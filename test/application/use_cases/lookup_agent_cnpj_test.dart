import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_profile_lookup_gateways.dart';
import 'package:plug_agente/application/use_cases/lookup_agent_cnpj.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:result_dart/result_dart.dart';

class _MockOpenCnpjLookup extends Mock implements IOpenCnpjLookup {}

void main() {
  group('LookupAgentCnpj', () {
    late _MockOpenCnpjLookup gateway;
    late LookupAgentCnpj useCase;

    setUp(() {
      gateway = _MockOpenCnpjLookup();
      useCase = LookupAgentCnpj(gateway);
    });

    test('returns ValidationFailure when sanitized input is shorter than 14 digits', () async {
      final result = await useCase(
        rawDocument: '123.456',
        invalidLengthMessage: 'invalid length',
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull();
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).message, equals('invalid length'));
      verifyNever(() => gateway.lookupCnpj(any()));
    });

    test('delegates sanitized digits to gateway when input has 14 digits', () async {
      when(() => gateway.lookupCnpj('11222333000181')).thenAnswer(
        (_) async => const Success(
          OpenCnpjCompanyData(
            cnpj: '11222333000181',
            legalName: 'ACME LTDA',
          ),
        ),
      );

      final result = await useCase(
        rawDocument: '11.222.333/0001-81',
        invalidLengthMessage: 'invalid length',
      );

      expect(result.isSuccess(), isTrue);
      verify(() => gateway.lookupCnpj('11222333000181')).called(1);
    });
  });
}
