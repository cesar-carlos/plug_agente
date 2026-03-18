import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

class MockClientTokenRepository extends Mock implements IClientTokenRepository {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

class MockAuthorizationDecisionCache extends Mock implements IAuthorizationDecisionCache {}

void main() {
  setUpAll(() {
    registerFallbackValue(_request());
    registerFallbackValue(
      TokenAuditEvent(
        eventType: TokenAuditEventType.create,
        timestamp: DateTime.utc(2026),
      ),
    );
  });

  group('Token cache invalidation use cases', () {
    late MockClientTokenRepository repository;
    late MockTokenAuditStore auditStore;
    late MockAuthorizationDecisionCache decisionCache;

    setUp(() {
      repository = MockClientTokenRepository();
      auditStore = MockTokenAuditStore();
      decisionCache = MockAuthorizationDecisionCache();
      when(() => auditStore.record(any())).thenAnswer((_) async {});
      when(() => decisionCache.invalidateAll()).thenAnswer((_) {});
    });

    test('revoke should invalidate authorization decision cache', () async {
      when(
        () => repository.revokeToken('token-1'),
      ).thenAnswer((_) async => const Success(unit));

      final useCase = RevokeClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
      );

      final result = await useCase.call('token-1');

      expect(result.isSuccess(), isTrue);
      verify(() => decisionCache.invalidateAll()).called(1);
    });

    test('delete should invalidate authorization decision cache', () async {
      when(
        () => repository.deleteToken('token-1'),
      ).thenAnswer((_) async => const Success(unit));

      final useCase = DeleteClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
      );

      final result = await useCase.call('token-1');

      expect(result.isSuccess(), isTrue);
      verify(() => decisionCache.invalidateAll()).called(1);
    });

    test('update should invalidate authorization decision cache', () async {
      when(
        () => repository.updateToken(
          'token-1',
          any(),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => Success(
          ClientTokenUpdateResult(
            tokenValue: 'rotated',
            version: 2,
            updatedAt: DateTime.utc(2026, 3, 17),
          ),
        ),
      );

      final useCase = UpdateClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
      );

      final result = await useCase.call(
        'token-1',
        _request(),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      verify(() => decisionCache.invalidateAll()).called(1);
    });
  });
}

ClientTokenCreateRequest _request() {
  return const ClientTokenCreateRequest(
    clientId: 'client-1',
    allTables: false,
    allViews: false,
    allPermissions: false,
    rules: [
      ClientTokenRule(
        resource: DatabaseResource(
          resourceType: DatabaseResourceType.table,
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
