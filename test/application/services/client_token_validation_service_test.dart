import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:result_dart/result_dart.dart';

class _MockResolver extends Mock implements IAuthorizationPolicyResolver {}

void main() {
  group('ClientTokenValidationService', () {
    test('validate returns failure without calling resolver when token is blank', () async {
      final resolver = _MockResolver();
      final service = ClientTokenValidationService(resolver);

      final result = await service.validate('  \t  ');

      expect(result.isError(), isTrue);
      verifyNever(() => resolver.resolvePolicy(any()));
    });

    test('validate delegates to resolver for non-empty token', () async {
      final resolver = _MockResolver();
      const policy = ClientTokenPolicy(
        clientId: 'c',
        allTables: true,
        allViews: false,
        allPermissions: true,
        rules: [],
      );
      when(
        () => resolver.resolvePolicy('abc'),
      ).thenAnswer((_) async => const Success(policy));
      final service = ClientTokenValidationService(resolver);

      final result = await service.validate('abc');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull(), equals(policy));
      verify(() => resolver.resolvePolicy('abc')).called(1);
    });
  });
}
