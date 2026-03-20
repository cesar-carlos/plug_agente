import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/delete_client_token.dart';
import 'package:plug_agente/application/use_cases/revoke_client_token.dart';
import 'package:plug_agente/application/use_cases/update_client_token.dart';
import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/entities/token_audit_event.dart';
import 'package:plug_agente/domain/repositories/i_authorization_decision_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_policy_cache.dart';
import 'package:plug_agente/domain/repositories/i_client_token_repository.dart';
import 'package:plug_agente/domain/repositories/i_token_audit_store.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

class MockClientTokenRepository extends Mock
    implements IClientTokenRepository {}

class MockTokenAuditStore extends Mock implements ITokenAuditStore {}

class MockAuthorizationDecisionCache extends Mock
    implements IAuthorizationDecisionCache {}

class MockClientTokenPolicyCache extends Mock
    implements IClientTokenPolicyCache {}

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
    late MockClientTokenPolicyCache policyCache;

    setUp(() {
      repository = MockClientTokenRepository();
      auditStore = MockTokenAuditStore();
      decisionCache = MockAuthorizationDecisionCache();
      policyCache = MockClientTokenPolicyCache();
      when(() => auditStore.record(any())).thenAnswer((_) async {});
      when(() => decisionCache.invalidateAll()).thenAnswer((_) {});
      when(
        () => decisionCache.invalidateForCredentialHash(any()),
      ).thenAnswer((_) {});
      when(() => policyCache.invalidate(any())).thenAnswer((_) {});
      when(() => policyCache.invalidateAll()).thenAnswer((_) {});
    });

    test(
      'revoke should invalidate caches for credential hash when secret known',
      () async {
        when(
          () => repository.getTokenById('token-1'),
        ).thenAnswer((_) async => _summary(tokenValue: 'secret-a'));
        when(
          () => repository.revokeToken('token-1'),
        ).thenAnswer((_) async => const Success(unit));

        final useCase = RevokeClientToken(
          repository,
          auditStore: auditStore,
          decisionCache: decisionCache,
          policyCache: policyCache,
        );

        final result = await useCase.call('token-1');

        expect(result.isSuccess(), isTrue);
        verifyNever(() => decisionCache.invalidateAll());
        verifyNever(() => policyCache.invalidateAll());
        verify(
          () => decisionCache.invalidateForCredentialHash(
            hashClientCredentialToken('secret-a'),
          ),
        ).called(1);
        verify(
          () => policyCache.invalidate(hashClientCredentialToken('secret-a')),
        ).called(1);
      },
    );

    test(
      'revoke should flush all caches when token secret unavailable',
      () async {
        when(() => repository.getTokenById('token-1')).thenAnswer((_) async {
          return _summary(tokenValue: null);
        });
        when(
          () => repository.revokeToken('token-1'),
        ).thenAnswer((_) async => const Success(unit));

        final useCase = RevokeClientToken(
          repository,
          auditStore: auditStore,
          decisionCache: decisionCache,
          policyCache: policyCache,
        );

        final result = await useCase.call('token-1');

        expect(result.isSuccess(), isTrue);
        verify(() => decisionCache.invalidateAll()).called(1);
        verify(() => policyCache.invalidateAll()).called(1);
        verifyNever(() => decisionCache.invalidateForCredentialHash(any()));
      },
    );

    test(
      'delete should invalidate caches for credential hash when secret known',
      () async {
        when(
          () => repository.getTokenById('token-1'),
        ).thenAnswer((_) async => _summary(tokenValue: 'secret-b'));
        when(
          () => repository.deleteToken('token-1'),
        ).thenAnswer((_) async => const Success(unit));

        final useCase = DeleteClientToken(
          repository,
          auditStore: auditStore,
          decisionCache: decisionCache,
          policyCache: policyCache,
        );

        final result = await useCase.call('token-1');

        expect(result.isSuccess(), isTrue);
        verifyNever(() => decisionCache.invalidateAll());
        verify(
          () => decisionCache.invalidateForCredentialHash(
            hashClientCredentialToken('secret-b'),
          ),
        ).called(1);
        verify(
          () => policyCache.invalidate(hashClientCredentialToken('secret-b')),
        ).called(1);
      },
    );

    test('update should invalidate old and new credential hashes', () async {
      when(
        () => repository.getTokenById('token-1'),
      ).thenAnswer((_) async => _summary(tokenValue: 'old-secret'));
      when(
        () => repository.updateToken(
          'token-1',
          any(),
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenAnswer(
        (_) async => Success(
          ClientTokenUpdateResult(
            tokenValue: 'new-secret',
            version: 2,
            updatedAt: DateTime.utc(2026, 3, 17),
          ),
        ),
      );

      final useCase = UpdateClientToken(
        repository,
        auditStore: auditStore,
        decisionCache: decisionCache,
        policyCache: policyCache,
      );

      final result = await useCase.call(
        'token-1',
        _request(),
        expectedVersion: 1,
      );

      expect(result.isSuccess(), isTrue);
      verifyNever(() => decisionCache.invalidateAll());
      verify(
        () => decisionCache.invalidateForCredentialHash(
          hashClientCredentialToken('old-secret'),
        ),
      ).called(1);
      verify(
        () => decisionCache.invalidateForCredentialHash(
          hashClientCredentialToken('new-secret'),
        ),
      ).called(1);
      verify(
        () => policyCache.invalidate(hashClientCredentialToken('old-secret')),
      ).called(1);
      verify(
        () => policyCache.invalidate(hashClientCredentialToken('new-secret')),
      ).called(1);
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

ClientTokenSummary _summary({required String? tokenValue}) {
  return ClientTokenSummary(
    id: 'token-1',
    clientId: 'client-1',
    createdAt: DateTime.utc(2026),
    isRevoked: false,
    allTables: false,
    allViews: false,
    allPermissions: true,
    rules: const [],
    tokenValue: tokenValue,
  );
}
