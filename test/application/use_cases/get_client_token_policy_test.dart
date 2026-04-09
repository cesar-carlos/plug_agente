import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/get_client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:result_dart/result_dart.dart';

class MockAuthorizationPolicyResolver extends Mock implements IAuthorizationPolicyResolver {}

void main() {
  group('GetClientTokenPolicy', () {
    late MockAuthorizationPolicyResolver resolver;
    late GetClientTokenPolicy useCase;

    setUp(() {
      resolver = MockAuthorizationPolicyResolver();
      useCase = GetClientTokenPolicy(resolver);
    });

    test('should return policy from resolver on success', () async {
      const policy = ClientTokenPolicy(
        clientId: 'c1',
        allTables: true,
        allViews: false,
        allPermissions: false,
        rules: [],
      );
      when(() => resolver.resolvePolicy('tok')).thenAnswer((_) async => const Success(policy));

      final result = await useCase.call('tok');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().clientId, equals('c1'));
      verify(() => resolver.resolvePolicy('tok')).called(1);
    });

    test('should return failure from resolver on error', () async {
      when(() => resolver.resolvePolicy('bad')).thenAnswer(
        (_) async => Failure(
          ConfigurationFailure.withContext(
            message: 'Token revoked',
            context: {'authorization': true, 'reason': 'token_revoked'},
          ),
        ),
      );

      final result = await useCase.call('bad');

      expect(result.isError(), isTrue);
      verify(() => resolver.resolvePolicy('bad')).called(1);
    });
  });
}
