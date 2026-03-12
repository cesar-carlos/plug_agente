import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

class MockAuthorizationPolicyResolver extends Mock
    implements IAuthorizationPolicyResolver {}

void main() {
  group('AuthorizeSqlOperation', () {
    late MockAuthorizationPolicyResolver resolver;
    late AuthorizeSqlOperation useCase;

    setUp(() {
      resolver = MockAuthorizationPolicyResolver();
      useCase = AuthorizeSqlOperation(
        SqlOperationClassifier(),
        ClientTokenValidationService(resolver),
      );
    });

    test('should authorize read operation when permission exists', () async {
      when(
        () => resolver.resolvePolicy(any()),
      ).thenAnswer((_) async => Success(_buildAllowedPolicy()));

      final result = await useCase.call(
        token: 'bearer-token',
        sql: 'SELECT * FROM dbo.users',
      );

      expect(result.isSuccess(), isTrue);
    });

    test('should deny operation when permission does not exist', () async {
      when(
        () => resolver.resolvePolicy(any()),
      ).thenAnswer((_) async => Success(_buildReadOnlyPolicy()));

      final result = await useCase.call(
        token: 'bearer-token',
        sql: 'DELETE FROM dbo.users WHERE id = 1',
      );

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) {
          final authFailure = failure as ConfigurationFailure;
          expect(authFailure.context['reason'], equals('missing_permission'));
        },
      );
    });
  });
}

ClientTokenPolicy _buildAllowedPolicy() {
  return const ClientTokenPolicy(
    clientId: 'client-acme',
    allTables: false,
    allViews: false,
    allPermissions: false,
    rules: <ClientTokenRule>[
      ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.unknown,
          name: 'dbo.users',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: true,
          canDelete: true,
        ),
        effect: ClientTokenRuleEffect.allow,
      ),
    ],
  );
}

ClientTokenPolicy _buildReadOnlyPolicy() {
  return const ClientTokenPolicy(
    clientId: 'client-acme',
    allTables: false,
    allViews: false,
    allPermissions: false,
    rules: <ClientTokenRule>[
      ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.unknown,
          name: 'dbo.users',
        ),
        permissions: ClientPermissionSet(
          canRead: true,
          canUpdate: false,
          canDelete: false,
        ),
        effect: ClientTokenRuleEffect.allow,
      ),
    ],
  );
}
