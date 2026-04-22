import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/client_token_validation_service.dart';
import 'package:plug_agente/application/services/sql_operation_classifier.dart';
import 'package:plug_agente/application/use_cases/authorize_sql_operation.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/errors/failures.dart' show ConfigurationFailure;
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_authorization_policy_resolver.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/stores/in_memory_authorization_decision_cache.dart';
import 'package:result_dart/result_dart.dart';

class MockAuthorizationPolicyResolver extends Mock implements IAuthorizationPolicyResolver {}

void main() {
  group('AuthorizeSqlOperation', () {
    late MockAuthorizationPolicyResolver resolver;
    late AuthorizeSqlOperation useCase;
    late InMemoryAuthorizationDecisionCache decisionCache;

    setUp(() {
      resolver = MockAuthorizationPolicyResolver();
      decisionCache = InMemoryAuthorizationDecisionCache();
      useCase = AuthorizeSqlOperation(
        SqlOperationClassifier(),
        ClientTokenValidationService(resolver),
        decisionCache: decisionCache,
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

    test(
      'should authorize CTE query using underlying table permission',
      () async {
        when(
          () => resolver.resolvePolicy(any()),
        ).thenAnswer((_) async => Success(_buildAllowedPolicy()));

        final result = await useCase.call(
          token: 'bearer-token',
          sql: 'WITH cte AS (SELECT * FROM dbo.users) SELECT * FROM cte',
        );

        expect(result.isSuccess(), isTrue);
      },
    );

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
          expect(
            authFailure.context['denied_resources'],
            equals(<String>['dbo.users']),
          );
          expect(authFailure.context['resource'], equals('dbo.users'));
          final um = authFailure.context['user_message'] as String?;
          expect(um, isNotNull);
          expect(um, contains('dbo.users'));
        },
      );
    });

    test(
      'should list all denied resources when multiple tables lack permission',
      () async {
        when(
          () => resolver.resolvePolicy(any()),
        ).thenAnswer((_) async => Success(_buildNoAccessPolicy()));

        final result = await useCase.call(
          token: 'bearer-token',
          sql: 'SELECT * FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as ConfigurationFailure;
            final denied = f.context['denied_resources'] as List<dynamic>?;
            expect(denied, isNotNull);
            expect(denied!.map((e) => e as String).toList(), hasLength(2));
            final names = denied.map((e) => e as String).toList()..sort();
            expect(names, equals(['dbo.orders', 'dbo.users']));
          },
        );
      },
    );

    test(
      'should list only resources denied in a join when one table is allowed',
      () async {
        when(
          () => resolver.resolvePolicy(any()),
        ).thenAnswer((_) async => Success(_buildAllowedPolicy()));

        final result = await useCase.call(
          token: 'bearer-token',
          sql: 'SELECT * FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure'),
          (failure) {
            final f = failure as ConfigurationFailure;
            expect(
              f.context['denied_resources'],
              equals(<String>['dbo.orders']),
            );
            expect(f.context['resource'], equals('dbo.orders'));
          },
        );
      },
    );

    test('should reuse cached decision and avoid resolver call', () async {
      when(
        () => resolver.resolvePolicy(any()),
      ).thenAnswer((_) async => Success(_buildAllowedPolicy()));

      final first = await useCase.call(
        token: 'bearer-token',
        sql: 'SELECT * FROM dbo.users',
      );
      final second = await useCase.call(
        token: 'bearer-token',
        sql: 'SELECT * FROM dbo.users',
      );

      expect(first.isSuccess(), isTrue);
      expect(second.isSuccess(), isTrue);
      verify(() => resolver.resolvePolicy(any())).called(1);
    });

    test(
      'should hit full decision cache when only some resource keys were stored',
      () async {
        when(
          () => resolver.resolvePolicy(any()),
        ).thenAnswer((_) async => Success(_buildAllowedPolicy()));

        await useCase.call(
          token: 'tok',
          sql: 'SELECT * FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );
        await useCase.call(
          token: 'tok',
          sql: 'SELECT * FROM dbo.users u JOIN dbo.orders o ON u.id = o.user_id',
        );

        verify(() => resolver.resolvePolicy(any())).called(1);
      },
    );

    test(
      'should not overwrite cached allow entries when validate fails for pending only',
      () async {
        when(() => resolver.resolvePolicy(any())).thenAnswer(
          (_) async => Failure(
            ConfigurationFailure.withContext(
              message: 'Token not found',
              context: const {
                'authorization': true,
                'reason': 'token_not_found',
              },
            ),
          ),
        );

        const token = 'opaque-token';
        final tokenHash = hashClientCredentialToken(token);
        final usersKey = '$tokenHash|read|dbo.users';
        decisionCache.put(
          usersKey,
          AuthorizationDecisionCacheEntry(
            allowed: true,
            expiresAt: DateTime.now().add(const Duration(minutes: 1)),
          ),
        );

        final result = await useCase.call(
          token: token,
          sql: 'SELECT * FROM dbo.users u INNER JOIN dbo.orders o ON u.id = o.user_id',
        );

        expect(result.isError(), isTrue);
        final usersStill = decisionCache.get(usersKey);
        expect(usersStill, isNotNull);
        expect(usersStill!.allowed, isTrue);

        final ordersKey = '$tokenHash|read|dbo.orders';
        final ordersEntry = decisionCache.get(ordersKey);
        expect(ordersEntry, isNotNull);
        expect(ordersEntry!.allowed, isFalse);
      },
    );
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

ClientTokenPolicy _buildNoAccessPolicy() {
  return const ClientTokenPolicy(
    clientId: 'client-acme',
    allTables: false,
    allViews: false,
    allPermissions: false,
    rules: <ClientTokenRule>[],
  );
}
